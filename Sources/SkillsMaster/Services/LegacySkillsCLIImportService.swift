import Foundation

/// Import legacy Skills CLI state into SkillsMaster's private canonical storage.
///
/// Import rules:
/// - Read entries from the legacy lock file (`~/.agents/.skill-lock.json`)
/// - Import only when a matching local skill directory can be found
/// - Merge into the private lock file without overwriting existing private entries
/// - Copy local files into `~/.skillsmaster/skills/<skill-id>` when needed
struct LegacySkillsCLIImportService {

    struct Result: Equatable {
        var scannedSkillCount: Int = 0
        var importedSkillNames: [String] = []
        var skippedExistingSkillNames: [String] = []
        var missingLocalSkillNames: [String] = []
    }

    enum ImportError: Error, LocalizedError {
        case legacyLockFileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .legacyLockFileNotFound(let path):
                "Legacy Skills CLI lock file not found: \(path)"
            }
        }
    }

    let legacyLockFilePath: URL
    let privateLockFilePath: URL
    let privateSharedSkillsURL: URL
    let legacySharedSkillsURL: URL
    let agentSkillDirectories: [URL]

    init(
        legacyLockFilePath: URL = LockFileManager.legacyPath,
        privateLockFilePath: URL = LockFileManager.defaultPath,
        privateSharedSkillsURL: URL = SkillScanner.sharedSkillsURL,
        legacySharedSkillsURL: URL = SkillScanner.legacySkillsURL,
        agentSkillDirectories: [URL] = AgentType.allCases.map(\.skillsDirectoryURL)
    ) {
        self.legacyLockFilePath = legacyLockFilePath
        self.privateLockFilePath = privateLockFilePath
        self.privateSharedSkillsURL = privateSharedSkillsURL
        self.legacySharedSkillsURL = legacySharedSkillsURL
        self.agentSkillDirectories = agentSkillDirectories
    }

    func importAndMerge() async throws -> Result {
        let legacyLockManager = LockFileManager(filePath: legacyLockFilePath)
        guard await legacyLockManager.exists else {
            throw ImportError.legacyLockFileNotFound(legacyLockFilePath.path)
        }

        let privateLockManager = LockFileManager(filePath: privateLockFilePath)
        try await privateLockManager.createIfNotExists()

        let legacyLock = try await legacyLockManager.read()
        let privateLock = try await privateLockManager.read()
        let fm = FileManager.default
        var result = Result(scannedSkillCount: legacyLock.skills.count)

        if !fm.fileExists(atPath: privateSharedSkillsURL.path) {
            try fm.createDirectory(at: privateSharedSkillsURL, withIntermediateDirectories: true)
        }

        for (skillName, entry) in legacyLock.skills.sorted(by: { $0.key < $1.key }) {
            if privateLock.skills[skillName] != nil {
                result.skippedExistingSkillNames.append(skillName)
                continue
            }

            let canonicalDir = privateSharedSkillsURL.appendingPathComponent(skillName)
            if !fm.fileExists(atPath: canonicalDir.path) {
                guard let locatedSkillDir = locateLocalSkillDirectory(named: skillName) else {
                    result.missingLocalSkillNames.append(skillName)
                    continue
                }
                try copySkillDirectoryIfNeeded(from: locatedSkillDir, to: canonicalDir, fileManager: fm)
            }

            try await privateLockManager.updateEntry(skillName: skillName, entry: entry)
            result.importedSkillNames.append(skillName)
        }

        return result
    }

    private func locateLocalSkillDirectory(named skillName: String) -> URL? {
        let candidates = [legacySharedSkillsURL] + agentSkillDirectories

        for root in candidates {
            let candidate = root.appendingPathComponent(skillName)
            let resolved = SymlinkManager.isSymlink(at: candidate)
                ? SymlinkManager.resolveSymlink(at: candidate).standardizedFileURL
                : candidate.standardizedFileURL

            let skillMDURL = resolved.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillMDURL.path) {
                return resolved
            }
        }

        return nil
    }

    private func copySkillDirectoryIfNeeded(from source: URL, to destination: URL, fileManager fm: FileManager) throws {
        guard !fm.fileExists(atPath: destination.path) else { return }

        let parent = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        try fm.copyItem(at: source, to: destination)
    }
}
