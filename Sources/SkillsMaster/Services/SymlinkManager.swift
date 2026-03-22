import Foundation

/// SymlinkManager is responsible for creating and removing symbolic links (F06 Agent Assignment)
///
/// Core Concepts:
/// - The "real copy" of all skills is stored in ~/.skillsmaster/skills/ (canonical location)
/// - Each Agent references the shared skill via symbolic link or a synced physical copy
/// - Example: ~/.claude/skills/agent-notifier -> ~/.skillsmaster/skills/agent-notifier
///
/// symbolic link is similar to Linux/macOS `ln -s`, a special file pointing to another file/directory
enum SymlinkManager {

    enum SymlinkError: Error, LocalizedError {
        case sourceNotFound(URL)
        case targetAlreadyExists(URL)
        case targetDirectoryNotFound(URL)
        case removalFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let url):
                "Skill source directory not found: \(url.path)"
            case .targetAlreadyExists(let url):
                "Target already exists: \(url.path)"
            case .targetDirectoryNotFound(let url):
                "Agent skills directory not found: \(url.path)"
            case .removalFailed(let url, let error):
                "Failed to remove symbolic link at \(url.path): \(error.localizedDescription)"
            }
        }
    }

    /// Create symbolic link for skill to specified Agent's skills directory
    ///
    /// - Parameters:
    ///   - source: canonical path of the skill (e.g. ~/.skillsmaster/skills/agent-notifier/)
    ///   - agent: target Agent type
    /// - Throws: SymlinkError
    ///
    /// Effect: agent.skillsDirectoryURL/skillName -> source
    static func createSymlink(from source: URL, to agent: AgentType) throws {
        let fm = FileManager.default
        let skillName = source.lastPathComponent
        let targetDir = agent.skillsDirectoryURL
        let targetURL = targetDir.appendingPathComponent(skillName)

        // 1. Verify source directory exists
        guard fm.fileExists(atPath: source.path) else {
            throw SymlinkError.sourceNotFound(source)
        }

        // 2. Ensure target Agent's skills directory exists, create if not
        if !fm.fileExists(atPath: targetDir.path) {
            // withIntermediateDirectories: true is similar to mkdir -p, creates parent directories recursively
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        // 3. Check if target location already exists
        guard !fm.fileExists(atPath: targetURL.path) else {
            throw SymlinkError.targetAlreadyExists(targetURL)
        }

        // 4. Create symbolic link
        // createSymbolicLink is equivalent to ln -s source targetURL
        try fm.createSymbolicLink(at: targetURL, withDestinationURL: source)
    }

    /// Remove symbolic link of a skill under specified Agent
    ///
    /// - Parameters:
    ///   - skillName: skill directory name
    ///   - agent: Agent type
    /// - Throws: SymlinkError
    static func removeSymlink(skillName: String, from agent: AgentType) throws {
        let fm = FileManager.default
        let targetURL = agent.skillsDirectoryURL.appendingPathComponent(skillName)

        // Verify the path is really a symbolic link to avoid deleting real directory by mistake
        guard isSymlink(at: targetURL) else {
            return // Not a symbolic link, return silently
        }

        do {
            try fm.removeItem(at: targetURL)
        } catch {
            throw SymlinkError.removalFailed(targetURL, error)
        }
    }

    /// Check whether the given path is a symbolic link
    ///
    /// FileManager.fileExists automatically resolves symbolic links (follows links),
    /// so we need to use attributesOfItem to read file attributes directly to judge
    static func isSymlink(at url: URL) -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileType = attrs[.type] as? FileAttributeType else {
            return false
        }
        return fileType == .typeSymbolicLink
    }

    /// Resolve the real path pointed to by a symbolic link (recursively resolve multi-level symbolic link chain)
    ///
    /// Use URL.resolvingSymlinksInPath() instead of single-level destinationOfSymbolicLink,
    /// to correctly handle multi-level symbolic link chains. Example:
    ///   ~/.copilot/skills/foo → ~/.claude/skills/foo → ~/.agents/skills/foo
    /// resolvingSymlinksInPath() will recursively resolve to the final real path ~/.agents/skills/foo
    ///
    /// If the path is not a symbolic link, return the original standardized path
    static func resolveSymlink(at url: URL) -> URL {
        // resolvingSymlinksInPath() is a recursive symbolic link resolution method provided by Foundation,
        // similar to Python's os.path.realpath() or Go's filepath.EvalSymlinks()
        // It will follow symbolic links until the final real path is found
        return url.resolvingSymlinksInPath()
    }

    /// Check whether an installed path points to the same managed skill as the canonical directory.
    ///
    /// Besides true symbolic links, this also treats a physical copy with the same `SKILL.md`
    /// content as a match. This is needed because some Agents must receive real files instead
    /// of symbolic links, but inheritance detection should still recognize them as the same skill.
    static func matchesCanonicalSkill(at installedURL: URL, canonicalURL: URL) -> Bool {
        if isSymlink(at: installedURL) {
            return resolveSymlink(at: installedURL).standardized.path == canonicalURL.standardized.path
        }

        if installedURL.standardized.path == canonicalURL.standardized.path {
            return true
        }

        let fm = FileManager.default
        let installedSkillMD = installedURL.appendingPathComponent("SKILL.md")
        let canonicalSkillMD = canonicalURL.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: installedSkillMD.path),
              fm.fileExists(atPath: canonicalSkillMD.path),
              let installedData = try? Data(contentsOf: installedSkillMD),
              let canonicalData = try? Data(contentsOf: canonicalSkillMD) else {
            return false
        }

        return installedData == canonicalData
    }

    /// Get installation info of skill across all Agents (including inherited installations)
    ///
    /// Uses two-pass scan strategy:
    /// 1. First pass: Check direct installations under each Agent's own skills directory
    /// 2. Second pass: For Agents without direct installation, check their additionalReadableSkillsDirectories,
    ///    mark as inherited installation (isInherited: true) if found
    ///
    /// Priority rule: If Agent already has this skill in its own directory (direct installation), do not add inherited installation
    /// e.g. if ~/.copilot/skills/foo exists, do not inherit from ~/.claude/skills/foo
    static func findInstallations(skillName: String, canonicalURL: URL) -> [SkillInstallation] {
        var installations: [SkillInstallation] = []
        /// Record which Agents have direct installation, for second pass filtering
        /// Set is similar to Java's HashSet, used for O(1) lookup
        var agentsWithDirectInstallation = Set<AgentType>()

        // ========== First pass: Direct installation scan ==========
        for agentType in AgentType.allCases {

            let skillURL = agentType.skillsDirectoryURL.appendingPathComponent(skillName)

            // Check if skill exists in this Agent's skills directory
            guard FileManager.default.fileExists(atPath: skillURL.path) else {
                continue
            }

            let isLink = isSymlink(at: skillURL)

            // If it's a symbolic link, verify it ultimately points to the same canonical location
            // Use resolvingSymlinksInPath() to recursively resolve, handling multi-level symbolic link chains
            if isLink {
                if matchesCanonicalSkill(at: skillURL, canonicalURL: canonicalURL) {
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: true
                    ))
                    agentsWithDirectInstallation.insert(agentType)
                }
            } else {
                // Not a symbolic link, means it's an original file (agent-local skill)
                installations.append(SkillInstallation(
                    agentType: agentType,
                    path: skillURL,
                    isSymlink: false
                ))
                agentsWithDirectInstallation.insert(agentType)
            }
        }

        // ========== Second pass: Inherited installation scan ==========
        // For Agents without direct installation, check other Agent directories it can additionally read
        for agentType in AgentType.allCases {
            // If already has direct installation, skip (direct installation has higher priority)
            guard !agentsWithDirectInstallation.contains(agentType) else { continue }

            // Iterate through list of directories this Agent can additionally read
            for additionalDir in agentType.additionalReadableSkillsDirectories {
                let skillURL = additionalDir.url.appendingPathComponent(skillName)

                guard FileManager.default.fileExists(atPath: skillURL.path) else {
                    continue
                }

                // Verify this path (after resolving symbolic link) indeed points to the same canonical skill
                if matchesCanonicalSkill(at: skillURL, canonicalURL: canonicalURL) {
                    // Inherited installation found: skill exists in source Agent directory, current Agent can read it
                    installations.append(SkillInstallation(
                        agentType: agentType,
                        path: skillURL,
                        isSymlink: isSymlink(at: skillURL),
                        isInherited: true,
                        inheritedFrom: additionalDir.sourceAgent
                    ))
                    // Stop on first match (avoid duplicate inherited installations for same Agent)
                    break
                }
            }
        }

        return installations
    }
}
