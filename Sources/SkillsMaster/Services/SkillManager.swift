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

    enum TranslationAvailability: Equatable {
        case unknown
        case installed
        case supportedButNotInstalled
        case unavailable
    }

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

    /// 统一的更新检查结果，兼容 Git 与 marketplace 版本语义。
    struct UpdateCheckResult {
        let hasUpdate: Bool
        let remoteHash: String?
        let remoteCommitHash: String?
        let remoteVersion: String?
    }

    // MARK: - Published State (UI-bound state)

    /// 当前已发现的全部 skills（已去重）。
    var skills: [Skill] = []

    /// 当前检测到的全部 Agents。
    var agents: [Agent] = []

    /// 每个 Agent 的默认安装方式。
    var defaultInstallModes: [AgentType: AgentInstallMode] = [:]

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
    /// 首次 `refresh()` 时会从配置文件中加载，并驱动 sidebar 中的 `Repositories` 区域。
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

    /// 当前中文翻译能力状态。
    /// 仅当系统支持且已安装英文 -> 简体中文离线翻译包时，详情页才会展示逐段中文译文。
    var translationAvailability: TranslationAvailability = .unknown

    /// 详情页手动翻译开关的会话内状态。
    /// 以调用方提供的稳定 memory key 为索引，跨窗口共享，但不落盘。
    private var manualTranslationStateByKey: [String: Bool] = [:]

    struct TranslationPackPrompt: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var translationPackPrompt: TranslationPackPrompt?

    // MARK: - Dependencies

    private let scanner = SkillScanner()
    private let detector = AgentDetector()
    private let lockFileManager = LockFileManager()
    private let watcher = FileSystemWatcher()
    /// 负责 application update 的检查、下载与安装。
    private let updateChecker = UpdateChecker()
    /// 用于 Git 来源安装与更新检查的 Git service。
    private let gitService = GitService()
    /// SkillsHub marketplace service，用于版本检查与 archive 下载。
    private let skillsHubService = SkillsHubService()
    /// F12：SkillsMaster 私有的 commit hash cache，与 `.skill-lock.json` 解耦。
    private let commitHashCache = CommitHashCache()
    /// 管理用户配置的 custom repositories。
    let repositoryManager = RepositoryManager()
    private let installModeStore: AgentInstallModeStore
    private let translationService: any EnglishToChineseTranslating
    private let translationPackAvailabilityChecker: any TranslationPackAvailabilityChecking
    private let localSkillImportService = LocalSkillImportService()
    private let legacySkillsCLIImportService = LegacySkillsCLIImportService()
    private static let dontShowTranslationPackPromptKey = "translationPackPromptDontShowAgain"
    private var hasShownTranslationPackPromptThisLaunch = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        installModeStore: AgentInstallModeStore = AgentInstallModeStore(),
        translationService: any EnglishToChineseTranslating = TranslationService(),
        translationPackAvailabilityChecker: any TranslationPackAvailabilityChecking = TranslationPackAvailabilityChecker()
    ) {
        self.installModeStore = installModeStore
        self.translationService = translationService
        self.translationPackAvailabilityChecker = translationPackAvailabilityChecker
        self.defaultInstallModes = installModeStore.loadAll()
        setupFileWatcher()
    }

    var shouldShowChineseTranslation: Bool {
        translationAvailability == .installed
    }

    func isShowingManualTranslation(for memoryKey: String) -> Bool {
        manualTranslationStateByKey[memoryKey] ?? false
    }

    func toggleManualTranslation(for memoryKey: String) {
        manualTranslationStateByKey[memoryKey] = !isShowingManualTranslation(for: memoryKey)
    }

    func translateEnglishParagraphToChinese(_ text: String) async throws -> String {
        do {
            return try await translationService.translateEnglishToChinese(text)
        } catch TranslationService.TranslationError.unavailable {
            if translationAvailability != .installed {
                translationAvailability = .supportedButNotInstalled
                presentTranslationPackPromptIfNeeded()
            }
            throw TranslationService.TranslationError.unavailable
        }
    }

    func prepareSkillContentTranslationIfNeeded(translationEnabledOnThisScreen: Bool) async {
        guard translationEnabledOnThisScreen else { return }

        if translationAvailability == .unknown || translationAvailability == .supportedButNotInstalled {
            let availability = await translationPackAvailabilityChecker.englishToSimplifiedChinese()
            translationAvailability = switch availability {
            case .installed:
                .installed
            case .supportedButNotInstalled:
                .supportedButNotInstalled
            case .unavailable:
                .unavailable
            }
        }

        presentTranslationPackPromptIfNeeded()
    }

    func dismissTranslationPackPrompt() {
        translationPackPrompt = nil
    }

    func dontShowTranslationPackPromptAgain() {
        UserDefaults.standard.set(true, forKey: Self.dontShowTranslationPackPromptKey)
        translationPackPrompt = nil
    }

    private func presentTranslationPackPromptIfNeeded() {
        let dontShowAgain = UserDefaults.standard.bool(forKey: Self.dontShowTranslationPackPromptKey)
        let shouldShowPrompt = TranslationPackPromptPolicy.shouldShowPrompt(
            translationEnabledOnThisScreen: translationAvailability == .supportedButNotInstalled,
            dontShowAgain: dontShowAgain,
            hasShownThisLaunch: hasShownTranslationPackPromptThisLaunch
        )
        guard shouldShowPrompt else { return }

        hasShownTranslationPackPromptThisLaunch = true
        translationPackPrompt = TranslationPackPrompt(
            title: "需要启用系统翻译能力",
            message: "要显示 Skill 文档的中文译文，请先确认系统 Translate app 可用，并已安装英文到简体中文的离线翻译语言包。处理完成后重新打开详情页即可看到逐段中文翻译。"
        )
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
        let previousRemoteState = Dictionary(
            uniqueKeysWithValues: skills.map {
                (
                    $0.id,
                    (
                        hasUpdate: $0.hasUpdate,
                        remoteTreeHash: $0.remoteTreeHash,
                        remoteCommitHash: $0.remoteCommitHash,
                        remoteVersion: $0.remoteVersion
                    )
                )
            }
        )

        // Load repositories config from disk and append the fixed LocalSkill source when enabled.
        await reloadRepositories()

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

            // 读取并填充私有 lock file 信息。
            // 这里会先使 cache 失效，确保读到磁盘上的最新数据。
            // 手动兼容导入等操作可能已经修改了 lock file。
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
                if let previous = previousRemoteState[skills[i].id] {
                    skills[i].remoteTreeHash = previous.remoteTreeHash
                    skills[i].remoteCommitHash = previous.remoteCommitHash
                    skills[i].remoteVersion = previous.remoteVersion
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

    private func reloadRepositories() async {
        var loadedRepositories = await repositoryManager.loadAll()
        loadedRepositories.removeAll { $0.isLocalCollection }

        if isLocalSkillRepositoryEnabled {
            loadedRepositories.insert(.localSkillRepository(), at: 0)
        }

        repositories = loadedRepositories
    }

    private var isLocalSkillRepositoryEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.localSkillRepositoryEnabledKey)
    }

    private func setLocalSkillRepositoryEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: Constants.localSkillRepositoryEnabledKey)
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

    /// Import legacy Skills CLI lock data and local skill files into SkillsMaster's private storage.
    func importFromSkillsCLI() async throws -> LegacySkillsCLIImportService.Result {
        let result = try await legacySkillsCLIImportService.importAndMerge()
        await refresh()
        return result
    }

    // MARK: - Agent Install Mode

    /// 获取指定 Agent 的默认安装方式；未配置时回退到 `软链接`。
    func installMode(for agent: AgentType) -> AgentInstallMode {
        defaultInstallModes[agent] ?? .symlink
    }

    /// 更新指定 Agent 的默认安装方式，并立即迁移当前由 SkillsMaster 管理的 direct install。
    func updateDefaultInstallMode(_ mode: AgentInstallMode, for agent: AgentType) async throws {
        guard installMode(for: agent) != mode else { return }

        defaultInstallModes[agent] = mode
        installModeStore.setMode(mode, for: agent)

        do {
            try migrateManagedDirectInstalls(for: agent, to: mode)
            await refresh()
        } catch {
            await refresh()
            throw error
        }
    }

    // MARK: - F04: Skill Deletion

    /// Delete a skill
    ///
    /// Deletion flow:
    /// 1. Remove direct installations from all Agents (symbolic links or physical copies; skip inherited installations)
    /// 2. Delete canonical directory (actual files)
    /// 3. Update lock file
    /// 4. Refresh data
    func deleteSkill(_ skill: Skill) async throws {
        // 1. Remove all direct installations (skip inherited installations)
        for installation in skill.installations where !installation.isInherited {
            try removeDirectInstall(
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
        try syncCopiedDirectInstallations(for: skill)
        await refresh()
    }

    // MARK: - F06: Agent Assignment (Toggle Symlink)

    /// Install skill to specified Agent using that Agent's configured default mode.
    func assignSkill(_ skill: Skill, to agent: AgentType) async throws {
        try materializeSkill(
            skill.id,
            from: skill.canonicalURL,
            to: agent,
            mode: installMode(for: agent),
            replaceExisting: false
        )
        await refresh()
    }

    /// Uninstall skill from specified Agent (delete symbolic link or physical copy)
    func unassignSkill(_ skill: Skill, from agent: AgentType) async throws {
        try removeDirectInstall(skillName: skill.id, from: agent)
        await refresh()
    }

    /// Toggle skill installation status on specified Agent
    ///
    /// Each Agent only manages its own direct install — SkillsMaster never touches
    /// another Agent's directory. Cross-directory reading is each Agent's own runtime
    /// behavior, which SkillsMaster does not interfere with.
    ///
    /// Toggle behavior:
    /// - Has direct install (symbolic link or physical copy in agent's own dir) → remove it
    /// - No direct install (regardless of inherited status) → materialize into that agent's own dir
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
            // 如果当前目录下什么都没有，就在这个 Agent 自己的目录里按默认方式创建 direct install。
            // 无论它之前是否通过继承方式可见，这里都可以正常建立直接安装。
            try await assignSkill(skill, to: agent)
        }
    }

    // MARK: - Git-Based Install

    /// 把已 clone repository 中的 skill 安装到本地 canonical 目录。
    ///
    /// 当前安装流程包括：获取 tree hash、复制文件、按 Agent 默认方式落盘、更新 lock file，最后刷新 UI。
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

        let sourceDir = GitService.skillDirectoryURL(in: repoDir, folderPath: skill.folderPath)

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

    func scanLocalImportCandidates(
        at selectionURL: URL,
        includeHiddenPaths: Bool
    ) async throws -> [LocalSkillImportService.Candidate] {
        try await localSkillImportService.scanCandidates(
            at: selectionURL,
            includeHiddenPaths: includeHiddenPaths
        )
    }

    /// 把本地 skill 导入到 SkillsMaster canonical 目录，并标记为 LocalSkill 来源。
    func importLocalSkill(
        from sourceURL: URL,
        skillName: String
    ) async throws {
        let trimmedName = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ImportError.parseFailed("Skill name cannot be empty.")
        }

        let fm = FileManager.default
        let standardizedSourceURL = sourceURL.standardizedFileURL
        let values = try standardizedSourceURL.resourceValues(forKeys: [.isDirectoryKey])

        let importDirectoryURL: URL
        let cleanupRootURL: URL?

        if values.isDirectory == true {
            let skillMDURL = standardizedSourceURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMDURL.path) else {
                throw ImportError.skillMDNotFound(standardizedSourceURL.path)
            }
            importDirectoryURL = standardizedSourceURL
            cleanupRootURL = nil
        } else {
            guard standardizedSourceURL.lastPathComponent == "SKILL.md" else {
                throw ImportError.skillMDNotFound(standardizedSourceURL.path)
            }
            let tempRoot = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-LocalImport-\(UUID().uuidString)")
            let tempSkillDirectory = tempRoot.appendingPathComponent(trimmedName)
            try fm.createDirectory(at: tempSkillDirectory, withIntermediateDirectories: true)
            try fm.copyItem(
                at: standardizedSourceURL,
                to: tempSkillDirectory.appendingPathComponent("SKILL.md")
            )
            importDirectoryURL = tempSkillDirectory
            cleanupRootURL = tempRoot
        }

        defer {
            if let cleanupRootURL {
                try? fm.removeItem(at: cleanupRootURL)
            }
        }

        _ = try SkillMDParser.parse(fileURL: importDirectoryURL.appendingPathComponent("SKILL.md"))

        let canonicalDir = SkillScanner.sharedSkillsURL.appendingPathComponent(trimmedName)
        let existingSkill = skills.first { $0.id == trimmedName }
        let now = ISO8601DateFormatter().string(from: Date())
        let installedAt = existingSkill?.lockEntry?.installedAt ?? now
        let entry = LockEntry(
            source: SkillRepository.localSkillRepositorySource,
            sourceType: "local",
            sourceUrl: standardizedSourceURL.path,
            skillPath: "\(trimmedName)/SKILL.md",
            skillFolderHash: "",
            installedAt: installedAt,
            updatedAt: now
        )

        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        if !fm.fileExists(atPath: SkillScanner.sharedSkillsURL.path) {
            try fm.createDirectory(at: SkillScanner.sharedSkillsURL, withIntermediateDirectories: true)
        }
        try fm.copyItem(at: importDirectoryURL, to: canonicalDir)

        if let existingSkill {
            let refreshedSkill = Skill(
                id: existingSkill.id,
                canonicalURL: canonicalDir,
                metadata: existingSkill.metadata,
                frontmatterText: existingSkill.frontmatterText,
                markdownBody: existingSkill.markdownBody,
                scope: existingSkill.scope,
                installations: existingSkill.installations,
                lockEntry: existingSkill.lockEntry,
                hasUpdate: existingSkill.hasUpdate,
                remoteTreeHash: existingSkill.remoteTreeHash,
                remoteCommitHash: existingSkill.remoteCommitHash,
                remoteVersion: existingSkill.remoteVersion,
                localCommitHash: existingSkill.localCommitHash
            )
            try syncCopiedDirectInstallations(for: refreshedSkill)
        }

        await commitHashCache.removeHash(for: trimmedName)
        await commitHashCache.removeLinkedInfo(for: trimmedName)
        try? await commitHashCache.save()

        try await lockFileManager.createIfNotExists()
        try await lockFileManager.updateEntry(skillName: trimmedName, entry: entry)

        setLocalSkillRepositoryEnabled(true)
        await refresh()
    }

    /// 重新把 canonical 中的本地导入 skill 落到指定 Agent 目录。
    func installImportedLocalSkill(_ skill: Skill, targetAgents: Set<AgentType>) async throws {
        for agent in targetAgents {
            try materializeSkill(
                skill.id,
                from: skill.canonicalURL,
                to: agent,
                mode: installMode(for: agent),
                replaceExisting: true
            )
        }
        await refresh()
    }

    /// 安装 ClawHub skill 到 canonical 目录，并按目标 Agent 的默认方式完成 direct install。
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

    /// 安装 SkillsHub skill 到 canonical 目录，并按目标 Agent 的默认方式完成 direct install。
    func installSkillsHubSkill(
        skill: SkillsHubSkill,
        version: String,
        archiveData: Data,
        targetAgents: Set<AgentType>
    ) async throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-SkillsHub-\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let archiveURL = tempRoot.appendingPathComponent("\(skill.slug).zip")
        let extractedRoot = tempRoot.appendingPathComponent("extracted")
        try archiveData.write(to: archiveURL)
        try fm.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        try extractZipArchive(at: archiveURL, to: extractedRoot)

        guard let extractedSkillDir = try locateSkillDirectory(in: extractedRoot) else {
            throw ImportError.skillMDNotFound("SkillsHub skill bundle for \(skill.slug)")
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let entry = LockEntry(
            source: skill.slug,
            sourceType: "skillhub",
            sourceUrl: "https://skillhub.tencent.com/",
            skillPath: "\(skill.slug)/SKILL.md",
            skillFolderHash: "",
            installedAt: now,
            updatedAt: now,
            sourceVersion: version,
            sourceUpdatedAt: isoTimestamp(fromMilliseconds: skill.updatedAtMilliseconds),
            originSourceType: skill.originSourceType,
            originSource: skill.originSource,
            originSourceUrl: skill.originSourceURL
        )

        try await persistInstalledSkillDirectory(
            from: extractedSkillDir,
            skillName: skill.slug,
            targetAgents: targetAgents,
            lockEntry: entry
        )
    }

    // MARK: - F12: Update Check

    /// 检查单个 skill 是否存在更新。
    ///
    /// 主要步骤是：读取 `lockEntry`、决定 shallow / full clone、获取远端 hash、与本地 hash 对比，最后清理临时目录。
    ///
    /// - Parameter skill: 待检查的 skill（必须带有 `lockEntry`）
    func checkForUpdate(skill: Skill) async throws -> UpdateCheckResult {
        guard let lockEntry = skill.lockEntry else {
            return UpdateCheckResult(hasUpdate: false, remoteHash: nil, remoteCommitHash: nil, remoteVersion: nil)
        }

        switch lockEntry.sourceType {
        case "local", "clawhub":
            return UpdateCheckResult(hasUpdate: false, remoteHash: nil, remoteCommitHash: nil, remoteVersion: nil)
        case "skillhub":
            return try await checkSkillsHubUpdate(skill: skill, lockEntry: lockEntry)
        default:
            return try await checkGitUpdate(skill: skill, lockEntry: lockEntry)
        }
    }

    private func checkGitUpdate(skill: Skill, lockEntry: LockEntry) async throws -> UpdateCheckResult {

        // 从 `skillPath` 推导出 folderPath。
        let folderPath = GitService.folderPath(for: lockEntry.skillPath)

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
        return UpdateCheckResult(
            hasUpdate: hasUpdate,
            remoteHash: hasUpdate ? remoteHash : nil,
            remoteCommitHash: hasUpdate ? remoteCommitHash : nil,
            remoteVersion: nil
        )
    }

    private func checkSkillsHubUpdate(skill: Skill, lockEntry: LockEntry) async throws -> UpdateCheckResult {
        let slug = lockEntry.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? skill.id : lockEntry.source
        let remoteSkill = try await skillsHubService.fetchSkill(slug: slug)
        guard let remoteVersion = remoteSkill.latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remoteVersion.isEmpty else {
            throw ImportError.parseFailed("SkillsHub did not provide a version for \(slug).")
        }

        let currentVersion = (lockEntry.sourceVersion ?? skill.metadata.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUpdate = currentVersion.isEmpty || VersionComparator.isNewer(current: currentVersion, latest: remoteVersion)
        return UpdateCheckResult(
            hasUpdate: hasUpdate,
            remoteHash: nil,
            remoteCommitHash: nil,
            remoteVersion: hasUpdate ? remoteVersion : nil
        )
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

        let skillsHubSkills = skillsWithLock.filter { $0.lockEntry?.sourceType == "skillhub" }
        for skill in skillsHubSkills {
            do {
                let result = try await checkForUpdate(skill: skill)
                applyUpdateCheckResult(result, to: skill.id, localCommitHash: skill.localCommitHash)
            } catch {
                updateStatuses[skill.id] = .error(error.localizedDescription)
            }
        }

        let grouped = Dictionary(
            grouping: skillsWithLock.filter { $0.lockEntry?.sourceType != "skillhub" }
        ) { $0.lockEntry!.sourceUrl }

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
                    let folderPath = GitService.folderPath(for: lockEntry.skillPath)

                    do {
                        let remoteHash = try await gitService.getTreeHash(for: folderPath, in: repoDir)
                        let hasUpdate = remoteHash != lockEntry.skillFolderHash

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

                        applyUpdateCheckResult(
                            UpdateCheckResult(
                                hasUpdate: hasUpdate,
                                remoteHash: hasUpdate ? remoteHash : nil,
                                remoteCommitHash: hasUpdate ? remoteCommitHash : nil,
                                remoteVersion: nil
                            ),
                            to: skill.id,
                            localCommitHash: currentLocalHash
                        )
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

    private func applyUpdateCheckResult(_ result: UpdateCheckResult, to skillID: String, localCommitHash: String?) {
        updateStatuses[skillID] = result.hasUpdate ? .hasUpdate : .upToDate

        if let index = skills.firstIndex(where: { $0.id == skillID }) {
            skills[index].hasUpdate = result.hasUpdate
            skills[index].remoteTreeHash = result.remoteHash
            skills[index].remoteCommitHash = result.remoteCommitHash
            skills[index].remoteVersion = result.remoteVersion
            skills[index].localCommitHash = localCommitHash
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
        let folderPath = GitService.folderPath(for: lockEntry.skillPath)

        // 1. Clone source repository
        let repoDir = try await gitService.shallowClone(repoURL: lockEntry.sourceUrl)

        // 2. Get new commit hash and write to cache
        let newCommitHash = try await gitService.getCommitHash(in: repoDir)
        await commitHashCache.setHash(for: skill.id, hash: newCommitHash)
        try? await commitHashCache.save()

        // 3. Copy files to overwrite canonical directory
        let fm = FileManager.default
        let sourceDir = GitService.skillDirectoryURL(in: repoDir, folderPath: folderPath)
        let canonicalDir = skill.canonicalURL

        // Delete old files then copy new files
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        try fm.copyItem(at: sourceDir, to: canonicalDir)
        try syncCopiedDirectInstallations(for: skill)

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

    /// 使用 SkillsHub archive 覆盖本地 canonical 目录，并刷新 lock entry 的版本信息。
    func updateSkillsHubSkill(_ skill: Skill, remoteVersion: String) async throws {
        guard let lockEntry = skill.lockEntry else { return }

        let slug = lockEntry.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? skill.id : lockEntry.source
        let remoteSkill = try await skillsHubService.fetchSkill(slug: slug)
        let archiveData = try await skillsHubService.downloadSkillArchive(slug: slug)

        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-SkillsHub-Update-\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let archiveURL = tempRoot.appendingPathComponent("\(slug).zip")
        let extractedRoot = tempRoot.appendingPathComponent("extracted")
        try archiveData.write(to: archiveURL)
        try fm.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        try extractZipArchive(at: archiveURL, to: extractedRoot)

        guard let extractedSkillDir = try locateSkillDirectory(in: extractedRoot) else {
            throw ImportError.skillMDNotFound("SkillsHub skill bundle for \(slug)")
        }

        let canonicalDir = skill.canonicalURL
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }
        try fm.copyItem(at: extractedSkillDir, to: canonicalDir)
        try syncCopiedDirectInstallations(for: skill)

        let now = ISO8601DateFormatter().string(from: Date())
        var updatedEntry = lockEntry
        updatedEntry.updatedAt = now
        updatedEntry.sourceVersion = remoteVersion
        updatedEntry.sourceUpdatedAt = isoTimestamp(fromMilliseconds: remoteSkill.updatedAtMilliseconds)
        updatedEntry.originSourceType = remoteSkill.originSourceType
        updatedEntry.originSource = remoteSkill.originSource
        updatedEntry.originSourceUrl = remoteSkill.originSourceURL
        try await lockFileManager.updateEntry(skillName: skill.id, entry: updatedEntry)

        updateStatuses[skill.id] = .notChecked
        await refresh()
    }

    // MARK: - Helper Methods

    /// 将一个 skill 按指定方式落到目标 Agent 目录。
    private func materializeSkill(
        _ skillName: String,
        from sourceURL: URL,
        to agent: AgentType,
        mode: AgentInstallMode,
        replaceExisting: Bool
    ) throws {
        let targetURL = agent.skillsDirectoryURL.appendingPathComponent(skillName)

        if replaceExisting {
            try removeDirectInstallIfExists(at: targetURL)
        } else if directInstallExists(at: targetURL) {
            throw SymlinkManager.SymlinkError.targetAlreadyExists(targetURL)
        }

        switch mode {
        case .symlink:
            try SymlinkManager.createSymlink(from: sourceURL, to: agent)
        case .copy:
            try copySkillDirectory(from: sourceURL, to: targetURL, replaceExisting: false)
        }
    }

    /// 删除 Agent 目录下的 direct install，不区分 symbolic link 或真实目录。
    private func removeDirectInstall(skillName: String, from agent: AgentType) throws {
        let targetURL = agent.skillsDirectoryURL.appendingPathComponent(skillName)
        try removeDirectInstallIfExists(at: targetURL)
    }

    private func removeDirectInstallIfExists(at targetURL: URL) throws {
        guard directInstallExists(at: targetURL) else { return }
        try FileManager.default.removeItem(at: targetURL)
    }

    private func directInstallExists(at url: URL) -> Bool {
        SymlinkManager.isSymlink(at: url) || FileManager.default.fileExists(atPath: url.path)
    }

    private func copySkillDirectory(from sourceURL: URL, to targetURL: URL, replaceExisting: Bool) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceURL.path) else {
            throw SymlinkManager.SymlinkError.sourceNotFound(sourceURL)
        }

        let parentDir = targetURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if replaceExisting, directInstallExists(at: targetURL) {
            try fm.removeItem(at: targetURL)
        }

        try fm.copyItem(at: sourceURL, to: targetURL)
    }

    /// 同步所有“物理复制” direct install，使其重新覆盖到最新事实源内容。
    private func syncCopiedDirectInstallations(for skill: Skill) throws {
        for installation in skill.installations where !installation.isInherited && !installation.isSymlink {
            // canonical 就是该 direct install 本身时，说明它是原始源目录，不需要自我覆盖。
            guard installation.path.standardized.path != skill.canonicalURL.standardized.path else { continue }
            try copySkillDirectory(from: skill.canonicalURL, to: installation.path, replaceExisting: true)
        }
    }

    /// 迁移某个 Agent 当前由 SkillsMaster 管理的 direct install。
    ///
    /// 只迁移“事实源不在该 Agent 自身目录”的 direct install，避免去改写用户手工放在
    /// 该 Agent 目录中的 agent-local skill。
    private func migrateManagedDirectInstalls(for agent: AgentType, to mode: AgentInstallMode) throws {
        let targetDir = agent.skillsDirectoryURL.standardized.path

        for skill in skills {
            guard skill.installations.contains(where: { $0.agentType == agent && !$0.isInherited }) else { continue }

            let canonicalParent = skill.canonicalURL.deletingLastPathComponent().standardized.path
            guard canonicalParent != targetDir else { continue }
            guard FileManager.default.fileExists(atPath: skill.canonicalURL.path) else { continue }

            try materializeSkill(
                skill.id,
                from: skill.canonicalURL,
                to: agent,
                mode: mode,
                replaceExisting: true
            )
        }
    }

    /// Get local commit hash for specified skill (read from CommitHashCache)
    ///
    /// This method is exposed for ViewModel use because commitHashCache is private.
    /// Call after checkForUpdate to get the commit hash that may have been newly obtained via backfill.
    func getCachedCommitHash(for skillName: String) async -> String? {
        await commitHashCache.getHash(for: skillName)
    }

    /// 统一安装落盘流程：复制到 canonical 目录 -> 按 Agent 默认方式建立 direct install -> 更新 lock file -> refresh。
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
            try materializeSkill(
                skillName,
                from: canonicalDir,
                to: agent,
                mode: installMode(for: agent),
                replaceExisting: true
            )
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

    private func isoTimestamp(fromMilliseconds milliseconds: Int64?) -> String? {
        guard let milliseconds else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
        // 当仓库目录名与本地 skill.id 不一致时，严格按 id 匹配会失败。
        // 这里复用 findSkill 走多策略匹配（目录名 → metadata.name → folderPath 末段 → 单 skill 兜底）。
        let discoveredSkills = await gitService.scanSkillsInRepo(repoDir: repoDir)
        guard let matched = GitService.findSkill(matching: skill.id, in: discoveredSkills) else {
            throw LinkError.skillNotFoundInRepo(skill.id)
        }

        // 4. Get tree hash and commit hash
        let treeHash = try await gitService.getTreeHash(for: matched.folderPath, in: repoDir)
        let commitHash = try await gitService.getCommitHash(in: repoDir)

        // 5. Sync remote files to local canonical directory
        // Ensure local files match the stored skillFolderHash,
        // otherwise hash comparison baseline in subsequent checkForUpdate will be inaccurate
        let fm = FileManager.default
        let sourceDir = GitService.skillDirectoryURL(in: repoDir, folderPath: matched.folderPath)
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

        try syncCopiedDirectInstallations(for: skill)

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
        if repo.isLocalCollection {
            setLocalSkillRepositoryEnabled(true)
            await reloadRepositories()
            return
        }
        try await repositoryManager.add(repo)
        do {
            if repo.authType.requiresToken,
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
        await reloadRepositories()
    }

    /// Remove a custom repository by ID from the config file.
    ///
    /// Does NOT delete the local clone from disk — leaves that to the user.
    func removeRepository(id: UUID) async {
        if id == SkillRepository.localSkillRepositoryID {
            setLocalSkillRepositoryEnabled(false)
            await reloadRepositories()
            repoSyncStatuses.removeValue(forKey: id)
            return
        }
        await repositoryManager.remove(id: id)
        await reloadRepositories()
        repoSyncStatuses.removeValue(forKey: id)
    }

    /// Update an existing custom repository configuration.
    ///
    /// Used for editable per-repository settings (for example: startup sync toggle).
    func updateRepository(_ repo: SkillRepository) async {
        guard !repo.isLocalCollection else { return }
        await repositoryManager.update(repo)
        await reloadRepositories()
    }

    /// Sync (clone or pull) a single repository and update its status in the UI.
    ///
    /// Updates `repoSyncStatuses[id]` to `.syncing` while in progress,
    /// then to `.success(date)` or `.error(message)` when done.
    func syncRepository(id: UUID) async {
        if id == SkillRepository.localSkillRepositoryID { return }
        guard let repo = repositories.first(where: { $0.id == id }) else { return }
        repoSyncStatuses[id] = .syncing

        do {
            try await repositoryManager.sync(repo: repo)
            // Reload so lastSyncedAt is updated
            await reloadRepositories()
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
