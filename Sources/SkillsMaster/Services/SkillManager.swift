import Foundation
import Combine

/// `SkillManager` 是整个 skill 管理流程的核心 orchestrator。
///
/// 它会组合多个底层 `Service`（如 scanner、parser、lock file、symbolic link、file watcher），
/// 对外提供统一的 CRUD / refresh / install / update 入口。
///
/// `@Observable` 用于驱动 SwiftUI 的状态刷新，`@MainActor` 则保证所有 UI state 更新都发生在 main thread。
@MainActor
@Observable
final class SkillManager {

    // MARK: - Error Types

    /// 手动关联 repository 时使用的错误类型。
    /// 通过 `LocalizedError` 提供适合直接展示的错误描述。
    enum LinkError: Error, LocalizedError {
        /// No matching skill directory found in repository
        case skillNotFoundInRepo(String)
        /// Git operation failed
        case gitError(String)

        var errorDescription: String? {
            switch self {
            case .skillNotFoundInRepo(let name):
                "Skill '\(name)' not found in repository"
            case .gitError(let message):
                message
            }
        }
    }

    /// 导入安装相关错误（本地导入 / ClawHub 安装共用）。
    enum ImportError: Error, LocalizedError {
        case directoryNotFound(String)
        case skillMDNotFound(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .directoryNotFound(let path):
                "Directory not found: \(path)"
            case .skillMDNotFound(let path):
                "No SKILL.md found in: \(path)"
            case .parseFailed(let message):
                "Failed to parse SKILL.md: \(message)"
            }
        }
    }

    /// ClawHub 安装结果。
    enum ClawHubInstallResult: Equatable {
        case installedFromArchive
        case installedSkillMarkdownOnly
    }

    // MARK: - Published State (UI-bound state)

    /// 当前已发现的全部 skills（已去重）。
    var skills: [Skill] = []

    /// 当前检测到的全部 Agents。
    var agents: [Agent] = []

    /// 当前是否处于 loading 状态。
    var isLoading = false

    /// 最近一次错误信息。
    var errorMessage: String?

    /// F12：当前是否正在执行批量更新检查。
    var isCheckingUpdates = false

    /// F12：更新状态表，以 `skill.id` 为 key，并在多次 refresh 之间保留。
    var updateStatuses: [String: SkillUpdateStatus] = [:]

    // MARK: - Custom Repositories State

    /// 用户配置的 custom repositories（支持 GitHub / GitLab）。
    /// 首次 `refresh()` 时会从配置文件中加载，并驱动 sidebar 中的 `Custom Repos` 区域。
    var repositories: [SkillRepository] = []

    /// 每个 repository 的同步状态（仅保存在内存中，不落盘）。
    var repoSyncStatuses: [UUID: SkillRepository.SyncStatus] = [:]

    // MARK: - App Update State (application update status)

    /// 最新的 Release 信息（`nil` 表示尚未检查，或当前没有可更新版本）。
    var appUpdateInfo: AppUpdateInfo?

    /// 当前是否正在检查 application update。
    var isCheckingAppUpdate = false

    /// 当前是否正在下载更新包。
    var isDownloadingUpdate = false

    /// 下载进度（`0.0 ~ 1.0`）。
    var downloadProgress: Double = 0

    /// 更新流程中的错误信息。
    var updateError: String?

    // MARK: - Dependencies

    private let scanner = SkillScanner()
    private let detector = AgentDetector()
    private let lockFileManager = LockFileManager()
    private let watcher = FileSystemWatcher()
    /// 负责 application update 的检查、下载与安装。
    private let updateChecker = UpdateChecker()
    /// F10 / F12：用于安装与更新检查的 Git service。
    private let gitService = GitService()
    /// F12：SkillsMaster 私有的 commit hash cache，与 `.skill-lock.json` 解耦。
    private let commitHashCache = CommitHashCache()
    /// 管理用户配置的 custom repositories。
    let repositoryManager = RepositoryManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupFileWatcher()
    }

    /// 建立 file system 监控，在目录变化时自动触发 `refresh()`。
    private func setupFileWatcher() {
        // `sink` 是 Combine 中的订阅入口；当 `watcher.onChange` 发出事件时，就在闭包里处理。
        watcher.onChange
            .sink { [weak self] in
                // 通过 `Task {}` 启动新的 async 任务。
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)  // 持有订阅，避免被提前释放
    }

    // MARK: - Core Operations

    /// 刷新全部数据：重新检测 Agents、扫描 skills，并加载 custom repositories。
    ///
    /// 同时会在后台触发需要自动同步的 repository，但不会阻塞主界面的加载。
    func refresh() async {
        isLoading = true
        errorMessage = nil

        // Load custom repositories config from disk (fast — JSON read only)
        repositories = await repositoryManager.loadAll()

        // 为启用了“启动时同步”的 repositories 触发后台同步（clone / pull）。
        // `Task { }` creates a detached child task that runs concurrently,
        // similar to Go's `go func(){}` — we don't await it here.
        Task { await syncAllRepositories() }

        do {
            // Execute Agent detection and Skill scanning concurrently
            // async let is similar to Go's goroutine + channel, both tasks run in parallel
            async let detectedAgents = detector.detectAll()
            async let scannedSkills = scanner.scanAll()

            agents = await detectedAgents
            var allSkills = try await scannedSkills

            // 读取并填充 lock file 信息。
            // 这里会先使 cache 失效，确保读到磁盘上的最新数据。
            // 外部工具（例如 `npx skills`）可能已经修改了 lock file。
            await lockFileManager.invalidateCache()
            if await lockFileManager.exists {
                if let lockFile = try? await lockFileManager.read() {
                    for i in allSkills.indices {
                        allSkills[i].lockEntry = lockFile.skills[allSkills[i].id]
                    }
                }
            }

            // Synthesize LockEntry for skills without lockEntry but with manual link info
            // So these skills can reuse existing update check flows (checkForUpdate, checkAllUpdates)
            let linkedInfos = await commitHashCache.getAllLinkedInfos()
            for i in allSkills.indices {
                if allSkills[i].lockEntry == nil, let linked = linkedInfos[allSkills[i].id] {
                    // Synthesize LockEntry: fields aligned with LinkedSkillInfo
                    // installedAt/updatedAt use link time (for UI display only)
                    allSkills[i].lockEntry = LockEntry(
                        source: linked.source,
                        sourceType: linked.sourceType,
                        sourceUrl: linked.sourceUrl,
                        skillPath: linked.skillPath,
                        skillFolderHash: linked.skillFolderHash,
                        installedAt: linked.linkedAt,
                        updatedAt: linked.linkedAt
                    )
                }
            }

            skills = allSkills

            // F12: Restore previous update status (refresh should not clear update check results)
            // Also load local commit hash from CommitHashCache
            // Restore hasUpdate boolean from SkillUpdateStatus enum: only .hasUpdate counts as having an update
            for i in skills.indices {
                if let status = updateStatuses[skills[i].id] {
                    skills[i].hasUpdate = (status == .hasUpdate)
                }
                // Read local commit hash from CommitHashCache
                // Used for displaying hash comparison in UI and generating GitHub compare URL
                skills[i].localCommitHash = await commitHashCache.getHash(for: skills[i].id)
            }

            // Start file system monitoring
            startWatching()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Start watching file system, monitor all relevant directories
    private func startWatching() {
        var paths: [URL] = [SkillScanner.sharedSkillsURL]
        // 同时监听旧目录，兼容仍然落在旧路径上的数据
        // (users or external tools may still place skills there)
        if SkillScanner.legacySkillsURL.path != SkillScanner.sharedSkillsURL.path,
           FileManager.default.fileExists(atPath: SkillScanner.legacySkillsURL.path) {
            paths.append(SkillScanner.legacySkillsURL)
        }
        for agent in AgentType.allCases {
            paths.append(agent.skillsDirectoryURL)
        }
        watcher.startWatching(paths: paths)
    }

    // MARK: - F04: Skill Deletion

    /// Delete a skill
    ///
    /// Deletion flow:
    /// 1. Remove direct installation symbolic links from all Agents (skip inherited installations)
    /// 2. Delete canonical directory (actual files)
    /// 3. Update lock file
    /// 4. Refresh data
    ///
    /// Inherited installation symbolic links don't need separate deletion: they point to symbolic links in the source Agent directory,
    /// and the source Agent's symbolic link will be deleted in step 1; even if not deleted, after the canonical directory is removed
    /// they become dangling symbolic links, which don't affect functionality
    func deleteSkill(_ skill: Skill) async throws {
        // 1. Remove all direct installation symbolic links (skip inherited installations)
        for installation in skill.installations where installation.isSymlink && !installation.isInherited {
            try SymlinkManager.removeSymlink(
                skillName: skill.id,
                from: installation.agentType
            )
        }

        // 2. Delete canonical directory
        let fm = FileManager.default
        if fm.fileExists(atPath: skill.canonicalURL.path) {
            try fm.removeItem(at: skill.canonicalURL)
        }

        // 3. Update lock file (if there's a record)
        if skill.lockEntry != nil {
            try await lockFileManager.removeEntry(skillName: skill.id)
        }

        // 4. Refresh list
        await refresh()
    }

    // MARK: - F05: Save Edited Skill

    /// Save edited skill (update SKILL.md)
    func saveSkill(_ skill: Skill, metadata: SkillMetadata, markdownBody: String) async throws {
        let content = try SkillMDParser.serialize(metadata: metadata, markdownBody: markdownBody)
        let skillMDURL = skill.canonicalURL.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDURL, atomically: true, encoding: .utf8)
        await refresh()
    }

    // MARK: - F06: Agent Assignment (Toggle Symlink)

    /// Install skill to specified Agent (create symbolic link)
    func assignSkill(_ skill: Skill, to agent: AgentType) async throws {
        try SymlinkManager.createSymlink(from: skill.canonicalURL, to: agent)
        await refresh()
    }

    /// Uninstall skill from specified Agent (delete symbolic link)
    func unassignSkill(_ skill: Skill, from agent: AgentType) async throws {
        try SymlinkManager.removeSymlink(skillName: skill.id, from: agent)
        await refresh()
    }

    /// Toggle skill installation status on specified Agent
    ///
    /// Each Agent only manages its own directory's symbolic link — SkillsMaster never touches
    /// another Agent's directory. Cross-directory reading is each Agent's own runtime
    /// behavior, which SkillsMaster does not interfere with.
    ///
    /// Toggle behavior:
    /// - Has direct install (symbolic link in agent's own dir) → remove it
    /// - No direct install (regardless of inherited status) → create symbolic link in agent's own dir
    /// - If agent only has an inherited installation, toggling ON creates a direct install (override)
    ///
    /// IMPORTANT: We check the file system directly instead of relying on skill.installations,
    /// because the passed-in `skill` is a struct value copy captured by SwiftUI's Binding closure.
    /// Due to race conditions with FileSystemWatcher-triggered refreshes, the captured `skill`
    /// may be stale by the time this async method executes. Checking the actual file system
    /// ensures we always make the correct decision regardless of any data staleness.
    func toggleAssignment(_ skill: Skill, agent: AgentType) async throws {
        // Check the actual file system state instead of relying on potentially stale skill.installations.
        // This avoids the race condition where a FileSystemWatcher refresh re-renders the view,
        // causing the Binding closure's captured `skill` to have outdated installation data.
        //
        // Use isSymlink OR fileExists to cover all cases:
        // - isSymlink: detects symbolic links including dangling ones (uses lstat, does NOT follow links)
        // - fileExists: detects real directories (follows symbolic links, so needed for non-symbolic link case)
        let targetURL = agent.skillsDirectoryURL.appendingPathComponent(skill.id)
        let hasDirectInstall = SymlinkManager.isSymlink(at: targetURL)
            || FileManager.default.fileExists(atPath: targetURL.path)

        if hasDirectInstall {
            // Something exists at agent's skills dir → remove it (symbolic link or real directory)
            try await unassignSkill(skill, from: agent)
        } else {
            // 如果当前目录下什么都没有，就在这个 Agent 自己的目录里创建 direct symbolic link。
            // 无论它之前是否通过继承方式可见，这里都可以正常建立直接安装。
            try await assignSkill(skill, to: agent)
        }
    }

    // MARK: - F10: One-Click Install

    /// 把已 clone repository 中的 skill 安装到本地 canonical 目录。
    ///
    /// 当前安装流程包括：获取 tree hash、复制文件、创建 symbolic link、更新 lock file，最后刷新 UI。
    ///
    /// - Parameters:
    ///   - repoDir: 已 clone 的本地临时目录
    ///   - skill: 待安装的 skill 信息
    ///   - repoSource: repository 的 source 标识
    ///   - repoURL: 完整 repository URL
    ///   - sourceType: 写入 lock entry 的 source 类型
    ///   - targetAgents: 要安装到的 Agent 集合
    func installSkill(
        from repoDir: URL,
        skill: GitService.DiscoveredSkill,
        repoSource: String,
        repoURL: String,
        sourceType: String = "github",
        targetAgents: Set<AgentType>
    ) async throws {
        // 1. 获取 tree hash。
        let treeHash = try await gitService.getTreeHash(for: skill.folderPath, in: repoDir)

        // 1.5 获取 commit hash，并写入私有 `CommitHashCache`。
        // 后续生成 GitHub compare URL 时会用到这个值。
        let commitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: commitHash)
        try await commitHashCache.save()

        let sourceDir = repoDir.appendingPathComponent(skill.folderPath)

        // 使用 ISO 8601 时间戳，保持与 `npx skills` 一致。
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: repoSource,
            sourceType: sourceType,
            sourceUrl: repoURL,
            skillPath: skill.skillMDPath,
            skillFolderHash: treeHash,
            installedAt: now,
            updatedAt: now
        )
        try await persistInstalledSkillDirectory(
            from: sourceDir,
            skillName: skill.id,
            targetAgents: targetAgents,
            lockEntry: entry
        )
    }

    /// 安装 ClawHub skill 到 canonical 目录，并为目标 Agent（默认 OpenClaw）建立 symbolic link。
    ///
    /// - archive 安装成功时返回 `.installedFromArchive`
    /// - 若 archive 不可用但 `SKILL.md` 可用，则 fallback 为 markdown-only 安装并返回 `.installedSkillMarkdownOnly`
    func installClawHubSkill(
        slug: String,
        version: String,
        detailPageURL: String,
        skillContent: String?,
        archiveData: Data?,
        targetAgents: Set<AgentType>
    ) async throws -> ClawHubInstallResult {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-ClawHub-\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: slug,
            sourceType: "clawhub",
            sourceUrl: detailPageURL,
            skillPath: "\(slug)/SKILL.md",
            skillFolderHash: "",
            installedAt: now,
            updatedAt: now
        )

        // 仅用于 future-proof：当前 lock file 不记录 version，但参数用于接口语义对齐。
        _ = version

        if let archiveData {
            let archiveURL = tempRoot.appendingPathComponent("\(slug).zip")
            let extractedRoot = tempRoot.appendingPathComponent("extracted")
            try archiveData.write(to: archiveURL)
            try fm.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

            do {
                try extractZipArchive(at: archiveURL, to: extractedRoot)
                if let extractedSkillDir = try locateSkillDirectory(in: extractedRoot) {
                    try await persistInstalledSkillDirectory(
                        from: extractedSkillDir,
                        skillName: slug,
                        targetAgents: targetAgents,
                        lockEntry: entry
                    )
                    return .installedFromArchive
                }
            } catch {
                if skillContent == nil {
                    throw error
                }
            }
        }

        guard let skillContent else {
            throw ImportError.skillMDNotFound("ClawHub skill bundle for \(slug)")
        }

        let markdownOnlyDir = tempRoot.appendingPathComponent(slug)
        try fm.createDirectory(at: markdownOnlyDir, withIntermediateDirectories: true)
        let skillMDURL = markdownOnlyDir.appendingPathComponent("SKILL.md")
        try skillContent.write(to: skillMDURL, atomically: true, encoding: .utf8)

        do {
            _ = try SkillMDParser.parse(fileURL: skillMDURL)
        } catch {
            throw ImportError.parseFailed(error.localizedDescription)
        }

        try await persistInstalledSkillDirectory(
            from: markdownOnlyDir,
            skillName: slug,
            targetAgents: targetAgents,
            lockEntry: entry
        )
        return .installedSkillMarkdownOnly
    }

    // MARK: - F12: Update Check

    /// 检查单个 skill 是否存在更新。
    ///
    /// 主要步骤是：读取 `lockEntry`、决定 shallow / full clone、获取远端 hash、与本地 hash 对比，最后清理临时目录。
    ///
    /// - Parameter skill: 待检查的 skill（必须带有 `lockEntry`）
    /// - Returns: `(是否有更新, 远端 tree hash, 远端 commit hash)`
    func checkForUpdate(skill: Skill) async throws -> (hasUpdate: Bool, remoteHash: String?, remoteCommitHash: String?) {
        guard let lockEntry = skill.lockEntry else {
            return (false, nil, nil)
        }
        // ClawHub / Local 安装不走 Git 仓库更新检查。
        guard lockEntry.sourceType != "local", lockEntry.sourceType != "clawhub" else {
            return (false, nil, nil)
        }

        // 从 `skillPath` 推导出 folderPath。
        let folderPath: String
        if lockEntry.skillPath.hasSuffix("/SKILL.md") {
            folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
        } else {
            folderPath = lockEntry.skillPath
        }

        // 检查 `CommitHashCache` 中是否已有本地 commit hash。
        let localCommitHash = await commitHashCache.getHash(for: skill.id)
        // 如果没有 commit hash（常见于旧 skill），就需要 full clone 来回填。
        let needsBackfill = localCommitHash == nil

        // 根据是否需要 backfill 决定 clone 深度。
        let repoDir = try await gitService.cloneRepo(repoURL: lockEntry.sourceUrl, shallow: !needsBackfill)
        defer {
            // 使用 `defer` 确保函数无论如何返回，都能清理临时目录。
            Task { await gitService.cleanupTempDirectory(repoDir) }
        }

        // 获取远端 tree hash。
        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)

        // 获取远端 commit hash。
        let remoteCommitHash = try await gitService.getCommitHash(in: repoDir)

        // 如果本地缺少 commit hash，就回查 git history 做 backfill。
        if needsBackfill {
            if let foundHash = try await gitService.findCommitForTreeHash(
                treeHash: lockEntry.skillFolderHash, folderPath: folderPath, in: repoDir
            ) {
                // 找到匹配的 commit hash 后写入 cache，下次就不需要重复搜索。
                await commitHashCache.setHash(for: skill.id, hash: foundHash)
                try? await commitHashCache.save()
            }
        }

        // 对比本地与远端 hash。
        let hasUpdate = remoteHash != lockEntry.skillFolderHash
        return (hasUpdate, remoteHash, remoteCommitHash)
    }

    /// Batch check updates for all skills with lockEntry
    ///
    /// Optimization strategy: group by sourceUrl, clone each repository only once,
    /// then batch get tree hash and commit hash for each skill to compare.
    ///
    /// Smart clone depth: check if any skill in the group lacks commit hash (from cache),
    /// if so use full clone (need to search git history for backfill), otherwise use shallow clone (faster).
    func checkAllUpdates() async {
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        // Collect all skills with lockEntry, group by sourceUrl
        // Dictionary(grouping:by:) is similar to Java Stream's Collectors.groupingBy()
        let skillsWithLock = skills.filter { skill in
            guard let sourceType = skill.lockEntry?.sourceType else { return false }
            return sourceType != "local" && sourceType != "clawhub"
        }

        // Set all skills to be checked to .checking state
        // So UI list immediately shows spinner, user knows which skills are being checked
        for skill in skillsWithLock {
            updateStatuses[skill.id] = .checking
        }

        let grouped = Dictionary(grouping: skillsWithLock) { $0.lockEntry!.sourceUrl }

        for (sourceUrl, groupSkills) in grouped {
            do {
                // Check if any skill in this group lacks commit hash
                // If so, need full clone to support backfill (search git history to restore commit hash)
                var needsFullClone = false
                for skill in groupSkills {
                    let cached = await commitHashCache.getHash(for: skill.id)
                    if cached == nil {
                        needsFullClone = true
                        break
                    }
                }

                // Clone each repository only once, decide clone depth based on whether backfill is needed
                let repoDir = try await gitService.cloneRepo(repoURL: sourceUrl, shallow: !needsFullClone)

                // Get remote latest commit hash (entire repository shares one HEAD commit)
                let remoteCommitHash = try await gitService.getCommitHash(in: repoDir)

                for skill in groupSkills {
                    guard let lockEntry = skill.lockEntry else { continue }

                    // Derive folderPath
                    let folderPath: String
                    if lockEntry.skillPath.hasSuffix("/SKILL.md") {
                        folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
                    } else {
                        folderPath = lockEntry.skillPath
                    }

                    do {
                        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)
                        let hasUpdate = remoteHash != lockEntry.skillFolderHash

                        // Update status dictionary: use enum value instead of boolean
                        updateStatuses[skill.id] = hasUpdate ? .hasUpdate : .upToDate

                        // Backfill: for skills lacking commit hash, search from git history
                        let localCached = await commitHashCache.getHash(for: skill.id)
                        var currentLocalHash = localCached
                        if localCached == nil {
                            if let foundHash = try? await gitService.findCommitForTreeHash(
                                treeHash: lockEntry.skillFolderHash, folderPath: folderPath, in: repoDir
                            ) {
                                await commitHashCache.setHash(for: skill.id, hash: foundHash)
                                currentLocalHash = foundHash
                            }
                        }

                        // Sync to skills array (find corresponding skill and update)
                        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
                            skills[index].hasUpdate = hasUpdate
                            skills[index].remoteTreeHash = hasUpdate ? remoteHash : nil
                            // Store remote commit hash for generating GitHub compare URL
                            skills[index].remoteCommitHash = hasUpdate ? remoteCommitHash : nil
                            // Update local commit hash (may have just been obtained via backfill)
                            skills[index].localCommitHash = currentLocalHash
                        }
                    } catch {
                        // Single skill check failed: mark as .error state, UI will show warning icon
                        updateStatuses[skill.id] = .error(error.localizedDescription)
                        continue
                    }
                }

                // Save cache once after backfill (reduce disk IO)
                try? await commitHashCache.save()

                // Clean up temporary directory
                await gitService.cleanupTempDirectory(repoDir)
            } catch {
                // Repository clone failed: mark all skills under this repo as .error
                for skill in groupSkills {
                    updateStatuses[skill.id] = .error(error.localizedDescription)
                }
                continue
            }
        }
    }

    /// Execute update: overwrite local with remote files, update lock entry
    ///
    /// - Parameters:
    ///   - skill: Skill to update
    ///   - remoteHash: Remote latest tree hash
    func updateSkill(_ skill: Skill, remoteHash: String) async throws {
        guard let lockEntry = skill.lockEntry else { return }

        // Derive folderPath
        let folderPath: String
        if lockEntry.skillPath.hasSuffix("/SKILL.md") {
            folderPath = String(lockEntry.skillPath.dropLast("/SKILL.md".count))
        } else {
            folderPath = lockEntry.skillPath
        }

        // 1. Clone source repository
        let repoDir = try await gitService.shallowClone(repoURL: lockEntry.sourceUrl)

        // 2. Get new commit hash and write to cache
        let newCommitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: newCommitHash)
        try? await commitHashCache.save()

        // 3. Copy files to overwrite canonical directory
        let fm = FileManager.default
        let sourceDir = repoDir.appendingPathComponent(folderPath)
        let canonicalDir = skill.canonicalURL

        // Delete old files then copy new files
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 4. Update lock entry (new hash + new updatedAt)
        let now = ISO8601DateFormatter().string(from: Date())
        var updatedEntry = lockEntry
        updatedEntry.skillFolderHash = remoteHash
        updatedEntry.updatedAt = now
        try await lockFileManager.updateEntry(skillName: skill.id, entry: updatedEntry)

        // 5. Clean up temporary directory
        await gitService.cleanupTempDirectory(repoDir)

        // 6. Clear update status (restore to unchecked state after update completes)
        updateStatuses[skill.id] = .notChecked

        // 7. Refresh UI
        await refresh()
    }

    // MARK: - Helper Methods

    /// Get local commit hash for specified skill (read from CommitHashCache)
    ///
    /// This method is exposed for ViewModel use because commitHashCache is private.
    /// Call after checkForUpdate to get the commit hash that may have been newly obtained via backfill.
    func getCachedCommitHash(for skillName: String) async -> String? {
        await commitHashCache.getHash(for: skillName)
    }

    /// Get a merged, deduplicated repo history list (lock file installed sources + scan history)
    ///
    /// Data sources:
    /// 1. `skills` array's `lockEntry.source`/`sourceUrl` (from lock file)
    /// 2. `commitHashCache.getRepoHistory()` (user's scan history)
    ///
    /// Dedup strategy: by `source` field (case-insensitive), lock file entries take priority
    /// since they have actual install records. Returns a tuple array for easy ViewModel consumption.
    ///
    /// - Returns: Deduplicated repo list, each with source (e.g. "owner/repo") and sourceUrl
    func getRepoHistory() async -> [(source: String, sourceUrl: String)] {
        // Use a Set to track seen sources (lowercased) for O(1) case-insensitive dedup.
        // GitHub URLs are case-insensitive, so "Owner/Repo" and "owner/repo" are the same repo.
        var seen = Set<String>()
        var result: [(source: String, sourceUrl: String)] = []

        // 1. Extract unique (source, sourceUrl) pairs from installed skills
        // Lock file entries are added first since installed repos are more valuable
        for skill in skills {
            guard let entry = skill.lockEntry else { continue }
            // Skip empty source (shouldn't happen in practice, but defensive programming)
            guard !entry.source.isEmpty else { continue }
            if seen.insert(entry.source.lowercased()).inserted {
                // insert returns (inserted: Bool, memberAfterInsert), similar to Go's map ok pattern
                result.append((source: entry.source, sourceUrl: entry.sourceUrl))
            }
        }

        // 2. Supplement with scan history (repos not already covered by lock file)
        let history = await commitHashCache.getRepoHistory()
        for entry in history {
            if seen.insert(entry.source.lowercased()).inserted {
                result.append((source: entry.source, sourceUrl: entry.sourceUrl))
            }
        }

        return result
    }

    /// Save a repo scan history entry to cache
    ///
    /// Called by SkillInstallViewModel after a successful scan,
    /// so the repo appears in the "Recent Repositories" list next time the Install Sheet opens.
    ///
    /// - Parameters:
    ///   - source: Repo source identifier (e.g. "crossoverJie/skills")
    ///   - sourceUrl: Full repo URL (e.g. "https://github.com/crossoverJie/skills.git")
    func saveRepoHistory(source: String, sourceUrl: String) async {
        await commitHashCache.addRepoHistory(source: source, sourceUrl: sourceUrl)
        try? await commitHashCache.save()
    }

    /// 统一安装落盘流程：复制到 canonical 目录 -> 建 symbolic link -> 更新 lock file -> refresh。
    private func persistInstalledSkillDirectory(
        from sourceURL: URL,
        skillName: String,
        targetAgents: Set<AgentType>,
        lockEntry: LockEntry
    ) async throws {
        let fm = FileManager.default
        let canonicalDir = SkillScanner.sharedSkillsURL.appendingPathComponent(skillName)

        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }

        if !fm.fileExists(atPath: SkillScanner.sharedSkillsURL.path) {
            try fm.createDirectory(at: SkillScanner.sharedSkillsURL, withIntermediateDirectories: true)
        }

        try fm.copyItem(at: sourceURL, to: canonicalDir)

        for agent in targetAgents {
            try? SymlinkManager.createSymlink(from: canonicalDir, to: agent)
        }

        try await lockFileManager.createIfNotExists()
        try await lockFileManager.updateEntry(skillName: skillName, entry: lockEntry)
        await refresh()
    }

    /// 使用 macOS 自带 `ditto` 解压 zip 包。
    private func extractZipArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipProcess.arguments = ["-xk", archiveURL.path, destinationURL.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw ImportError.parseFailed("Failed to extract ClawHub archive.")
        }
    }

    /// 在解压目录中递归定位第一个包含 `SKILL.md` 的目录。
    private func locateSkillDirectory(in rootURL: URL) throws -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: rootURL.appendingPathComponent("SKILL.md").path) {
            return rootURL
        }

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            if fm.fileExists(atPath: fileURL.appendingPathComponent("SKILL.md").path) {
                return fileURL
            }
        }

        return nil
    }

    /// Filter skills by Agent
    func skills(for agentType: AgentType) -> [Skill] {
        skills.filter { skill in
            skill.installations.contains { $0.agentType == agentType }
        }
    }

    /// Search skills (by name, description, and author/source)
    /// Besides matching displayName and description, also supports:
    /// - lockEntry?.source: repository source from lock file (e.g. "crossoverJie/skills"), suitable for filtering by organization/author
    /// - metadata.author: author field from SKILL.md frontmatter (optional)
    func search(query: String) -> [Skill] {
        guard !query.isEmpty else { return skills }
        let lowered = query.lowercased()
        return skills.filter {
            $0.displayName.lowercased().contains(lowered) ||
            $0.metadata.description.lowercased().contains(lowered) ||
            ($0.lockEntry?.source.lowercased().contains(lowered) ?? false) ||
            ($0.metadata.author?.lowercased().contains(lowered) ?? false)
        }
    }

    // MARK: - Link to Repository (manual repository linking)

    /// Manually link a skill without lockEntry to a GitHub repository
    ///
    /// Flow:
    /// 1. normalizeRepoURL() validates and normalizes URL input
    /// 2. shallow clone remote repository
    /// 3. scanSkillsInRepo scans skills in repository, matches by skill.id
    /// 4. Get tree hash + commit hash
    /// 5. Sync remote files to local canonical directory (ensure local files match hash)
    /// 6. Write to commitHashCache (linkedSkills + skills two maps)
    /// 7. refresh() to refresh UI
    ///
    /// Link 信息存储在 SkillsMaster 私有 cache（`~/.skillsmaster/.skillsmaster-cache.json`）中，
    /// does not modify skill-lock.json (to avoid affecting npx skills behavior).
    /// During refresh(), link info is read from cache and synthesized into LockEntry on Skill model,
    /// thus reusing existing update check flow.
    ///
    /// - Parameters:
    ///   - skill: Skill to link (must have no lockEntry)
    ///   - repoInput: User input repository address (supports "owner/repo" or full URL)
    func linkSkillToRepository(_ skill: Skill, repoInput: String) async throws {
        // 1. Validate and normalize URL
        let (repoURL, source) = try GitService.normalizeRepoURL(repoInput)

        // 2. shallow clone remote repository
        let repoDir: URL
        do {
            repoDir = try await gitService.shallowClone(repoURL: repoURL)
        } catch {
            throw LinkError.gitError(error.localizedDescription)
        }
        // defer ensures cleanup runs regardless of how function returns (similar to Go's defer)
        defer {
            Task { await gitService.cleanupTempDirectory(repoDir) }
        }

        // 3. Scan skills in repository, match by skill.id
        let discoveredSkills = await gitService.scanSkillsInRepo(repoDir: repoDir)
        guard let matched = discoveredSkills.first(where: { $0.id == skill.id }) else {
            throw LinkError.skillNotFoundInRepo(skill.id)
        }

        // 4. Get tree hash and commit hash
        let treeHash = try await gitService.getTreeHash(for: matched.folderPath, in: repoDir)
        let commitHash = try await gitService.getCommitHash(in: repoDir)

        // 5. Sync remote files to local canonical directory
        // Ensure local files match the stored skillFolderHash,
        // otherwise hash comparison baseline in subsequent checkForUpdate will be inaccurate
        let fm = FileManager.default
        let sourceDir = repoDir.appendingPathComponent(matched.folderPath)
        let canonicalDir = skill.canonicalURL

        // Delete old files then copy new files (consistent with installSkill/updateSkill)
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        // 确保父目录存在。
        let parentDir = canonicalDir.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        // copyItem recursively copies entire directory (similar to cp -r)
        try fm.copyItem(at: sourceDir, to: canonicalDir)

        // 6. Write to commitHashCache (two maps)
        // 6a. skills map: store commit hash (for subsequent compare URL)
        await commitHashCache.setHash(for: skill.id, hash: commitHash)

        // 6b. linkedSkills map: store complete link info (for synthesizing LockEntry during refresh)
        let now = ISO8601DateFormatter().string(from: Date())
        let linkedInfo = CommitHashCache.LinkedSkillInfo(
            source: source,
            sourceType: "github",
            sourceUrl: repoURL,
            skillPath: matched.skillMDPath,
            skillFolderHash: treeHash,
            linkedAt: now
        )
        await commitHashCache.setLinkedInfo(for: skill.id, info: linkedInfo)

        // Persist to disk
        try await commitHashCache.save()

        // 7. Refresh UI — refresh reads link info from cache and synthesizes LockEntry
        await refresh()
    }

    // MARK: - Custom Repository Management

    /// Add a new custom repository and persist it to the config file.
    ///
    /// - Parameter repo: A fully constructed SkillRepository (id, repoURL, localSlug, etc.)
    /// - Throws: RepositoryManager.RepositoryError if the repo already exists
    func addRepository(_ repo: SkillRepository) async throws {
        try await addRepository(repo, token: nil)
    }

    /// Add a new custom repository with optional HTTPS access token.
    ///
    /// Token is persisted in Keychain only; never written to JSON config.
    func addRepository(_ repo: SkillRepository, token: String?) async throws {
        try await repositoryManager.add(repo)
        do {
            if repo.authType == .httpsToken,
               let key = repo.credentialKey,
               let token,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try RepositoryCredentialStore.saveToken(token, for: key)
            }
        } catch {
            // Roll back repo config if keychain write fails.
            await repositoryManager.remove(id: repo.id)
            throw error
        }
        repositories = await repositoryManager.loadAll()
    }

    /// Remove a custom repository by ID from the config file.
    ///
    /// Does NOT delete the local clone from disk — leaves that to the user.
    func removeRepository(id: UUID) async {
        await repositoryManager.remove(id: id)
        repositories = await repositoryManager.loadAll()
        repoSyncStatuses.removeValue(forKey: id)
    }

    /// Update an existing custom repository configuration.
    ///
    /// Used for editable per-repository settings (for example: startup sync toggle).
    func updateRepository(_ repo: SkillRepository) async {
        await repositoryManager.update(repo)
        repositories = await repositoryManager.loadAll()
    }

    /// Sync (clone or pull) a single repository and update its status in the UI.
    ///
    /// Updates `repoSyncStatuses[id]` to `.syncing` while in progress,
    /// then to `.success(date)` or `.error(message)` when done.
    func syncRepository(id: UUID) async {
        guard let repo = repositories.first(where: { $0.id == id }) else { return }
        repoSyncStatuses[id] = .syncing

        do {
            try await repositoryManager.sync(repo: repo)
            // Reload so lastSyncedAt is updated
            repositories = await repositoryManager.loadAll()
            repoSyncStatuses[id] = .success(Date())
        } catch {
            repoSyncStatuses[id] = .error(error.localizedDescription)
        }
    }

    /// Sync all repositories configured to "sync on launch" in the background.
    ///
    /// Called automatically on startup by `refresh()`.
    /// Each repo's status is updated in `repoSyncStatuses` independently.
    func syncAllRepositories() async {
        for repo in repositories where repo.syncOnLaunch {
            await syncRepository(id: repo.id)
        }
    }

    // MARK: - App Update (application update flow)

    /// Check if SkillsMaster app itself has a new version
    ///
    /// Flow:
    /// 1. Read current version (from Info.plist or fallback to "dev")
    /// 2. "dev" version skips check (no .app bundle when launched via swift run in development)
    /// 3. Non-force mode respects 4-hour interval (avoid frequent GitHub API requests)
    /// 4. Call GitHub API to get latest Release
    /// 5. Compare versions using VersionComparator
    /// 6. If update available, set appUpdateInfo to trigger UI refresh
    ///
    /// - Parameter force: Whether to force check (ignore 4-hour interval, for manual trigger)
    func checkForAppUpdate(force: Bool = false) async {
        // Read current version
        // CFBundleShortVersionString is the version field in Info.plist
        // When launched via swift run, Bundle.main has no Info.plist, fallback to "dev"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        // "dev" version only skips automatic check (auto-trigger on app launch)
        // When user manually clicks "Check for Updates" (force=true), even dev version should execute check and show results
        // This allows testing update check flow in development environment
        if currentVersion == "dev" && !force { return }

        // Check 4-hour interval in non-force mode
        // force = true is for Settings page "Check for Updates" button (manual trigger, not limited by interval)
        if !force && !updateChecker.shouldAutoCheck() { return }

        isCheckingAppUpdate = true
        updateError = nil

        do {
            // Call GitHub API to get latest Release (throws version, errors no longer silently swallowed)
            let releaseInfo = try await updateChecker.fetchLatestRelease()

            // Record this check time (regardless of whether update exists, to avoid repeated requests in short time)
            updateChecker.recordCheckTime()

            // "dev" version is treated as always having updates (any Release counts as new version in development)
            // Release versions use VersionComparator for semantic comparison
            if currentVersion == "dev" || VersionComparator.isNewer(current: currentVersion, latest: releaseInfo.version) {
                appUpdateInfo = releaseInfo
            } else {
                // Current is already latest, clear previous update reminder (if any)
                appUpdateInfo = nil
            }
        } catch {
            // Silently ignore errors during automatic check (don't disturb user)
            // Show specific error message when user manually triggers (force=true) for troubleshooting
            if force {
                updateError = error.localizedDescription
            }
        }

        isCheckingAppUpdate = false
    }

    /// Execute app update: download zip → extract → replace .app → restart
    ///
    /// Call timing: User clicks "Update Now" button on Settings About page
    ///
    /// Flow:
    /// 1. Get download URL from appUpdateInfo
    /// 2. Download zip via UpdateChecker.downloadUpdate and report progress
    /// 3. Extract and replace via UpdateChecker.installUpdate
    /// 4. App will auto-restart (done by shell script)
    ///
    /// Error handling: Unlike detection phase, download/install errors will be shown to user
    func performUpdate() async {
        guard let updateInfo = appUpdateInfo else { return }

        isDownloadingUpdate = true
        downloadProgress = 0
        updateError = nil

        do {
            // Download zip file, update progress via closure callback
            // @MainActor is already marked on this class, so self.downloadProgress assignment executes on main thread
            // @Sendable closure needs Task { @MainActor in } to return to main thread to update UI state
            let zipPath = try await updateChecker.downloadUpdate(
                from: updateInfo.downloadURL
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }

            // Install update (extract → replace → restart)
            // Note: if installation succeeds, app will be terminated, subsequent code won't execute
            try await updateChecker.installUpdate(zipPath: zipPath)
        } catch {
            // Download or installation failed, show error message to user
            updateError = error.localizedDescription
            isDownloadingUpdate = false
        }
    }

    /// Dismiss app update reminder (user manually ignores)
    func dismissAppUpdate() {
        appUpdateInfo = nil
        updateError = nil
    }
}
