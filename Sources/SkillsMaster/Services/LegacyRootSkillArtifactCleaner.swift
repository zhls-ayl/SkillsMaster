import Foundation

/// Clean up stale artifacts left by the old root-level GitHub skill installation bug.
///
/// Historical issue:
/// - A repository whose `SKILL.md` lived at the repo root could be installed under
///   a temporary clone directory name like `SkillsMaster-<UUID>`.
/// - Later fixes stopped generating those IDs, but some old lock entries, private cache
///   entries, and broken Agent symlinks can remain on disk.
///
/// This cleaner is intentionally conservative:
/// - only considers `SkillsMaster-<UUID>` names
/// - only considers lock entries whose `skillPath` is root-level `SKILL.md`
/// - skips any candidate that still resolves to a real `SKILL.md` on disk
struct LegacyRootSkillArtifactCleaner {

    struct Result: Equatable {
        var removedSkillNames: [String] = []
    }

    let lockFilePath: URL
    let cacheFilePath: URL
    let sharedSkillsURL: URL
    let legacySkillsURL: URL
    let agentSkillDirectories: [URL]

    init(
        lockFilePath: URL = LockFileManager.defaultPath,
        cacheFilePath: URL = CommitHashCache.defaultPath,
        sharedSkillsURL: URL = SkillScanner.sharedSkillsURL,
        legacySkillsURL: URL = SkillScanner.legacySkillsURL,
        agentSkillDirectories: [URL] = AgentType.allCases.map(\.skillsDirectoryURL)
    ) {
        self.lockFilePath = lockFilePath
        self.cacheFilePath = cacheFilePath
        self.sharedSkillsURL = sharedSkillsURL
        self.legacySkillsURL = legacySkillsURL
        self.agentSkillDirectories = agentSkillDirectories
    }

    func cleanup() async throws -> Result {
        let lockFileManager = LockFileManager(filePath: lockFilePath)
        guard await lockFileManager.exists else {
            return Result()
        }

        let lockFile = try await lockFileManager.read()
        let cache = CommitHashCache(filePath: cacheFilePath)
        let fm = FileManager.default
        var result = Result()
        var cacheModified = false

        for (skillName, entry) in lockFile.skills.sorted(by: { $0.key < $1.key }) {
            guard isLegacyRootSkillArtifactName(skillName, lockEntry: entry) else { continue }
            guard !hasMaterializedSkill(named: skillName) else { continue }

            for root in cleanupRoots {
                let artifactURL = root.appendingPathComponent(skillName)
                guard pathExists(at: artifactURL, fileManager: fm) else { continue }
                try? fm.removeItem(at: artifactURL)
            }

            try await lockFileManager.removeEntry(skillName: skillName)
            await cache.removeHash(for: skillName)
            await cache.removeLinkedInfo(for: skillName)
            cacheModified = true
            result.removedSkillNames.append(skillName)
        }

        if cacheModified {
            try await cache.save()
        }

        return result
    }

    private var cleanupRoots: [URL] {
        var roots = [sharedSkillsURL]
        if legacySkillsURL.path != sharedSkillsURL.path {
            roots.append(legacySkillsURL)
        }
        roots.append(contentsOf: agentSkillDirectories)
        return roots
    }

    private func isLegacyRootSkillArtifactName(_ skillName: String, lockEntry: LockEntry) -> Bool {
        guard lockEntry.skillPath == "SKILL.md" else { return false }
        guard skillName.hasPrefix("SkillsMaster-") else { return false }
        let uuidPart = String(skillName.dropFirst("SkillsMaster-".count))
        return UUID(uuidString: uuidPart) != nil
    }

    private func hasMaterializedSkill(named skillName: String) -> Bool {
        let fm = FileManager.default

        for root in cleanupRoots {
            let url = root.appendingPathComponent(skillName)
            let resolvedURL = SymlinkManager.isSymlink(at: url)
                ? SymlinkManager.resolveSymlink(at: url)
                : url

            let skillMDURL = resolvedURL.appendingPathComponent("SKILL.md")
            if fm.fileExists(atPath: skillMDURL.path) {
                return true
            }
        }

        return false
    }

    private func pathExists(at url: URL, fileManager fm: FileManager) -> Bool {
        SymlinkManager.isSymlink(at: url) || fm.fileExists(atPath: url.path)
    }
}
