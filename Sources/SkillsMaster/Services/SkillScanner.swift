import Foundation

/// SkillScanner is responsible for scanning the file system to discover all installed skills
///
/// Scanning strategy:
/// 1. 先扫描 `~/.skillsmaster/skills/`（当前 canonical 存储目录）
/// 2. 再扫描 `~/.agents/skills/`（兼容旧数据与附加读取规则的旧目录）
/// 3. Then scan each Agent's skills directory
/// 4. Deduplicate via skill id: if a skill with the same name is found in multiple locations,
///    merge their installations into a single Skill model
///
/// This is similar to filepath.Walk in Go for traversing directory trees
actor SkillScanner {

    /// 当前 canonical skills 目录（`~/.skillsmaster/skills/`）
    /// Delegates to AgentType.sharedSkillsDirectoryURL for single source of truth
    static let sharedSkillsURL: URL = AgentType.sharedSkillsDirectoryURL

    /// 旧共享 skills 目录（`~/.agents/skills/`）。
    /// 这里继续保留扫描，是为了兼容尚未迁移的数据以及手工放置到旧目录的 skill。
    static let legacySkillsURL: URL = AgentType.legacySharedSkillsDirectoryURL

    /// Scan all skills, returning deduplicated results
    /// - Returns: Array of discovered skills (deduplicated, each skill name appears only once)
    func scanAll() async throws -> [Skill] {
        // Use skill id (directory name) as deduplication key, not canonicalURL.path
        // Reason: the same skill might be pointed to by different Agent symbolic links to different physical paths
        // e.g. ~/.copilot/skills/agent-notifier -> /path/to/dev/agent-notifier
        //      ~/.agents/skills/agent-notifier   (another physical path)
        // Although canonicalURL is different, skill id is the same, should be treated as same skill
        var skillMap: [String: Skill] = [:]

        // 1. Scan new canonical directory (~/.skillsmaster/skills/)
        // Use .unassigned as placeholder; final scope is determined in post-scan phase
        let globalSkills = scanDirectory(Self.sharedSkillsURL, scope: .unassigned)
        for skill in globalSkills {
            skillMap[skill.id] = skill
        }

        // 1.5. 扫描旧目录（`~/.agents/skills/`），兼容仍在旧路径上的数据
        // Skills placed here (manually or by external tools) should still be discovered.
        // Only add skills not already found in the new canonical directory (dedup by id).
        if Self.legacySkillsURL.path != Self.sharedSkillsURL.path {
            let legacySkills = scanDirectory(Self.legacySkillsURL, scope: .unassigned)
            for skill in legacySkills where skillMap[skill.id] == nil {
                skillMap[skill.id] = skill
            }
        }

        // 2. Scan each Agent's skills directory
        for agentType in AgentType.allCases {

            let agentSkills = scanDirectory(
                agentType.skillsDirectoryURL,
                scope: .agentLocal(agentType)
            )

            for skill in agentSkills {
                if var existingSkill = skillMap[skill.id] {
                    // Same name skill exists: merge installations (indicates same skill referenced by multiple Agents)
                    let newInstallations = skill.installations.filter { newInst in
                        !existingSkill.installations.contains(where: { $0.id == newInst.id })
                    }
                    existingSkill.installations.append(contentsOf: newInstallations)
                    skillMap[skill.id] = existingSkill
                } else {
                    // New skill: add directly
                    skillMap[skill.id] = skill
                }
            }
        }

        // ===== Post-scan: determine scope based on actual installation distribution =====
        // Scope should NOT depend on which directory was scanned first (cache vs agent).
        // Instead, scope is derived from how many Agents have this skill directly installed:
        //   - 0 direct installations (cache-only, not yet assigned to any Agent) → .unassigned
        //   - 1 direct installation → .agentLocal (belongs to that single Agent)
        //   - 2+ direct installations → .shared (genuinely shared across Agents)
        // Inherited installations (isInherited: true) are excluded because they represent
        // an Agent's ability to *read* another directory, not an explicit installation.
        for (id, var skill) in skillMap {
            let directInstallations = skill.installations.filter { !$0.isInherited }
            switch directInstallations.count {
            case 0:
                skill.scope = .unassigned
            case 1:
                skill.scope = .agentLocal(directInstallations[0].agentType)
            default:
                skill.scope = .shared
            }
            skillMap[id] = skill
        }

        // Return sorted by name
        return skillMap.values.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    /// Scan all skills in a single directory
    /// - Parameters:
    ///   - directory: Directory URL to scan
    ///   - scope: Corresponding scope for this directory
    /// - Returns: Array of discovered skills
    private func scanDirectory(_ directory: URL, scope: SkillScope) -> [Skill] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return []
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // compactMap: transform each element, filtering out nil results (similar to Java Stream map + filter)
        return contents.compactMap { itemURL in
            parseSkillDirectory(itemURL, scope: scope)
        }
    }

    /// Parse individual skill directory
    /// - Returns: Skill instance, or nil if directory is not a valid skill
    private func parseSkillDirectory(_ url: URL, scope: SkillScope) -> Skill? {
        let fm = FileManager.default
        let skillName = url.lastPathComponent

        // Resolve symbolic link to get canonical path
        let canonicalURL: URL
        if SymlinkManager.isSymlink(at: url) {
            canonicalURL = SymlinkManager.resolveSymlink(at: url)
        } else {
            canonicalURL = url
        }

        // Check if SKILL.md exists
        let skillMDURL = canonicalURL.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMDURL.path) else {
            return nil
        }

        // Parse SKILL.md
        let metadata: SkillMetadata
        let frontmatterText: String
        let markdownBody: String
        do {
            let result = try SkillMDParser.parse(fileURL: skillMDURL)
            metadata = result.metadata
            frontmatterText = result.frontmatterText
            markdownBody = result.markdownBody
        } catch {
            // Use default values on parse failure, do not block the entire scan
            metadata = SkillMetadata(name: skillName, description: "")
            frontmatterText = ""
            markdownBody = ""
        }

        // Find installation information for this skill across all Agents
        let installations = SymlinkManager.findInstallations(
            skillName: skillName,
            canonicalURL: canonicalURL
        )

        return Skill(
            id: skillName,
            canonicalURL: canonicalURL,
            metadata: metadata,
            frontmatterText: frontmatterText,
            markdownBody: markdownBody,
            scope: scope,
            installations: installations,
            lockEntry: nil  // lock entry populated later by SkillManager
        )
    }
}
