import Foundation

/// `MigrationManager` 负责一次性的路径迁移逻辑。
///
/// 当 SkillsMaster 把 canonical 存储从 `~/.agents/skills/` 迁移到 `~/.skillsmaster/skills/` 后，
/// 旧用户首次启动时需要自动完成数据迁移。
///
/// 当前迁移范围包括 skill 目录、私有 cache、repository 配置与 clone 目录，以及 Agent symbolic link 的重定向。
/// 自 `lock file` 私有化后，首次启动也会把旧的 `~/.agents/.skill-lock.json`
/// 复制到新的 `~/.skillsmaster/.skill-lock.json`，但不会删除旧文件。
///
/// Uses `enum` as a namespace (no instances) with static methods.
/// The migration is idempotent — safe to run multiple times.
enum MigrationManager {

    struct Paths {
        let oldSkillsDir: URL
        let oldCachePath: URL
        let oldReposConfigPath: URL
        let oldReposDir: URL
        let oldLockFilePath: URL
        let newSkillsDir: URL
        let newBaseDir: URL
        let newCachePath: URL
        let newReposConfigPath: URL
        let newReposDir: URL
        let newLockFilePath: URL

        static let `default` = Paths(
            oldSkillsDir: AgentType.legacySharedSkillsDirectoryURL,
            oldCachePath: URL(fileURLWithPath: NSString(string: "~/.agents/.skillsmaster-cache.json").expandingTildeInPath),
            oldReposConfigPath: URL(fileURLWithPath: NSString(string: "~/.agents/.skillsmaster-repos.json").expandingTildeInPath),
            oldReposDir: URL(fileURLWithPath: NSString(string: "~/.agents/repos").expandingTildeInPath),
            oldLockFilePath: LockFileManager.legacyPath,
            newSkillsDir: AgentType.sharedSkillsDirectoryURL,
            newBaseDir: URL(fileURLWithPath: NSString(string: "~/.skillsmaster").expandingTildeInPath),
            newCachePath: CommitHashCache.defaultPath,
            newReposConfigPath: URL(fileURLWithPath: NSString(string: Constants.skillReposConfigPath).expandingTildeInPath),
            newReposDir: URL(fileURLWithPath: NSString(string: Constants.reposBasePath).expandingTildeInPath),
            newLockFilePath: LockFileManager.defaultPath
        )
    }

    // MARK: - Public API

    /// Perform migration if needed. Safe to call multiple times (idempotent).
    ///
    /// Checks whether old paths contain data that should be moved to new paths.
    /// Skips individual steps if source doesn't exist or destination already has data.
    static func migrateIfNeeded() {
        migrateIfNeeded(paths: .default)
    }

    static func migrateIfNeeded(
        paths: Paths,
        fileManager fm: FileManager = .default
    ) {
        guard hasAnyLegacyArtifacts(paths: paths, fileManager: fm) else { return }

        // 确保新的基准目录 `~/.skillsmaster/` 已存在。
        try? fm.createDirectory(at: paths.newBaseDir, withIntermediateDirectories: true)

        // 1. Migrate skill directories (real directories only, not symbolic links)
        if fm.fileExists(atPath: paths.oldSkillsDir.path) {
            migrateSkillDirectories(paths: paths, fileManager: fm)
            // 2. Fix Agent symbolic links to point to new canonical path
            fixAgentSymlinks(paths: paths, fileManager: fm)
        }

        // 3. Migrate SkillsMaster private files
        moveFileIfNeeded(from: paths.oldCachePath, to: paths.newCachePath, fileManager: fm)
        moveFileIfNeeded(from: paths.oldReposConfigPath, to: paths.newReposConfigPath, fileManager: fm)
        moveDirIfNeeded(from: paths.oldReposDir, to: paths.newReposDir, fileManager: fm)

        // 4. Copy legacy lock file into the private canonical path once.
        copyFileIfNeeded(from: paths.oldLockFilePath, to: paths.newLockFilePath, fileManager: fm)
    }

    // MARK: - Private Helpers

    private static func hasAnyLegacyArtifacts(paths: Paths, fileManager fm: FileManager) -> Bool {
        [
            paths.oldSkillsDir,
            paths.oldCachePath,
            paths.oldReposConfigPath,
            paths.oldReposDir,
            paths.oldLockFilePath
        ].contains { fm.fileExists(atPath: $0.path) }
    }

    /// 把 skill 目录从旧 canonical 位置迁移到新位置。
    /// 这里只移动真实目录，不移动 symbolic link。
    /// typically created by agents like Codex and should be left alone.
    private static func migrateSkillDirectories(paths: Paths, fileManager fm: FileManager) {
        // Ensure new skills directory exists
        try? fm.createDirectory(at: paths.newSkillsDir, withIntermediateDirectories: true)

        guard let contents = try? fm.contentsOfDirectory(
            at: paths.oldSkillsDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for itemURL in contents {
            let name = itemURL.lastPathComponent
            let newURL = paths.newSkillsDir.appendingPathComponent(name)

            // Skip if already exists at new location (idempotent)
            guard !fm.fileExists(atPath: newURL.path) else { continue }

            // Only move real directories (not symbolic links)
            // `~/.agents/skills/` 中的 symbolic link 可能属于仍会读取该目录的 Agents。
            guard !SymlinkManager.isSymlink(at: itemURL) else { continue }

            // Move directory to new location
            // moveItem is atomic on the same filesystem (similar to rename() in POSIX)
            try? fm.moveItem(at: itemURL, to: newURL)
        }
    }

    /// 修复所有仍指向旧 canonical 路径的 Agent symbolic link，并重新指向新路径。
    private static func fixAgentSymlinks(paths: Paths, fileManager fm: FileManager) {
        for agentType in AgentType.allCases {
            let agentDir = agentType.skillsDirectoryURL
            guard fm.fileExists(atPath: agentDir.path) else { continue }

            guard let contents = try? fm.contentsOfDirectory(
                at: agentDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for itemURL in contents {
                guard SymlinkManager.isSymlink(at: itemURL) else { continue }

                // Read one-level symbolic link destination (not recursive resolve)
                // We want to check if the immediate target is in the old canonical dir
                guard let destination = try? fm.destinationOfSymbolicLink(atPath: itemURL.path) else {
                    continue
                }

                // Resolve relative path to absolute
                let absoluteDest: String
                if destination.hasPrefix("/") {
                    absoluteDest = destination
                } else {
                    // Relative symbolic link — resolve against the symbolic link's parent directory
                    absoluteDest = agentDir.appendingPathComponent(destination).standardized.path
                }

                // Check if symbolic link points to old canonical directory
                let oldPrefix = paths.oldSkillsDir.path
                guard absoluteDest.hasPrefix(oldPrefix) else { continue }

                // Extract skill name and compute new target
                let skillName = itemURL.lastPathComponent
                let newTarget = paths.newSkillsDir.appendingPathComponent(skillName)

                // Only relink if new target exists (migration step 1 moved it there)
                guard fm.fileExists(atPath: newTarget.path) else { continue }

                // Remove old symbolic link and create new one pointing to new canonical path
                try? fm.removeItem(at: itemURL)
                try? fm.createSymbolicLink(at: itemURL, withDestinationURL: newTarget)
            }
        }
    }

    /// Move a single file from old path to new path if source exists and destination does not.
    private static func moveFileIfNeeded(from source: URL, to destination: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        guard !fm.fileExists(atPath: destination.path) else { return }

        // Ensure parent directory exists
        let parent = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fm.moveItem(at: source, to: destination)
    }

    /// Move a directory from old path to new path if source exists and destination does not.
    private static func moveDirIfNeeded(from source: URL, to destination: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        guard !fm.fileExists(atPath: destination.path) else { return }

        // Ensure parent directory exists
        let parent = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fm.moveItem(at: source, to: destination)
    }

    /// Copy a single file from old path to new path if source exists and destination does not.
    /// We intentionally keep the old file in place as an external compatibility source.
    private static func copyFileIfNeeded(from source: URL, to destination: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        guard !fm.fileExists(atPath: destination.path) else { return }

        let parent = destination.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try? fm.copyItem(at: source, to: destination)
    }
}
