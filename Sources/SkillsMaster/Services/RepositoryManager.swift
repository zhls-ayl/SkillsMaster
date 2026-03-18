import Foundation

/// `RepositoryManager` 负责管理用户配置的 custom Git repositories，并把它们作为 Skills 来源。
///
/// 主要职责包括：
/// - 持久化 repository 配置
/// - clone 新仓库到本地目录
/// - 对已 clone 的仓库执行 pull
/// - 扫描本地仓库，发现可安装的 Skills
///
/// 由于这里会同时涉及 file I/O 与 git 操作，使用 `actor` 可以避免并发下的 data race，
/// 这也是本项目中 `LockFileManager`、`GitService` 等组件采用的同一模式。
actor RepositoryManager {

    enum ScanCacheStatus: Equatable {
        case hit
        case miss
        case bypassedDirtyWorkingTree

        var noticeMessage: String? {
            switch self {
            case .bypassedDirtyWorkingTree:
                return "检测到本地 clone 有未提交改动，本次已跳过仓库索引缓存。建议在原始工作区提交后再通过 Sync 拉取。"
            case .hit, .miss:
                return nil
            }
        }
    }

    struct ScanResult {
        let skills: [GitService.DiscoveredSkill]
        let cacheStatus: ScanCacheStatus
    }

    // MARK: - Error Types

    enum RepositoryError: Error, LocalizedError {
        case invalidURL(String)
        case cloneFailed(String)
        case alreadyExists(String)
        case notFound(UUID)
        case missingCredentials(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                "Invalid repository URL: \(url)"
            case .cloneFailed(let msg):
                "Failed to clone repository: \(msg)"
            case .alreadyExists(let slug):
                "A repository with local path '\(slug)' already exists"
            case .notFound(let id):
                "Repository with id \(id) not found"
            case .missingCredentials(let reason):
                reason
            }
        }
    }

    // MARK: - Persisted Config

    /// repository 配置文件的顶层 JSON 结构。
    private struct RepoConfig: Codable {
        var version: Int = 1
        var repositories: [SkillRepository] = []
    }

    // MARK: - Private State

    /// 内存中的 repository 列表缓存，与磁盘配置保持镜像关系。
    private var cachedRepos: [SkillRepository] = []

    /// 配置是否已经至少从磁盘加载过一次。
    private var isLoaded = false

    /// 供 clone / pull 复用的 `GitService` 实例。
    private let gitService = GitService()

    /// custom repository 的轻量扫描索引缓存。
    private let repositoryScanCache = RepositoryScanCache()

    // MARK: - Config File Path

    /// 展开 `~` 后得到的配置文件绝对路径。
    private var configFilePath: String {
        NSString(string: Constants.skillReposConfigPath).expandingTildeInPath
    }

    /// 展开 `~` 后得到的 repository 根目录绝对路径。
    private var reposBasePath: String {
        NSString(string: Constants.reposBasePath).expandingTildeInPath
    }

    // MARK: - Public API

    /// 从磁盘加载并返回全部 repository 配置。
    /// 首次调用时会真正读取文件，后续则直接返回内存 cache。
    func loadAll() async -> [SkillRepository] {
        if !isLoaded {
            await loadFromDisk()
        }
        return cachedRepos
    }

    /// 新增 repository 配置并持久化到磁盘。
    func add(_ repo: SkillRepository) async throws {
        if !isLoaded { await loadFromDisk() }

        var normalizedRepo = repo
        normalizedRepo.normalizeLocalSlugIfNeeded()

        // Prevent duplicate slugs (same remote repo added twice)
        if cachedRepos.contains(where: { $0.normalizedLocalSlug == normalizedRepo.normalizedLocalSlug }) {
            throw RepositoryError.alreadyExists(normalizedRepo.normalizedLocalSlug)
        }

        cachedRepos.append(normalizedRepo)
        await saveToDisk()
    }

    /// 按 ID 删除 repository 配置，并持久化变更。
    /// 注意：这里只删除配置，不会删除本地 clone 目录。
    func remove(id: UUID) async {
        if !isLoaded { await loadFromDisk() }
        let removed = cachedRepos.filter { $0.id == id }
        cachedRepos.removeAll { $0.id == id }
        for repo in removed {
            if let key = repo.credentialKey {
                RepositoryCredentialStore.deleteToken(for: key)
            }
            try? await repositoryScanCache.remove(repoID: repo.id)
        }
        await saveToDisk()
    }

    /// Update an existing repository's configuration (e.g. renamed by user).
    func update(_ repo: SkillRepository) async {
        if !isLoaded { await loadFromDisk() }
        var normalizedRepo = repo
        normalizedRepo.normalizeLocalSlugIfNeeded()
        if let idx = cachedRepos.firstIndex(where: { $0.id == normalizedRepo.id }) {
            cachedRepos[idx] = normalizedRepo
            await saveToDisk()
        }
    }

    /// Sync all repositories configured to sync on launch: clone if not yet cloned, pull otherwise.
    ///
    /// Runs each repository's sync sequentially to avoid hitting git's SSH connection limits.
    /// Errors are logged per-repository and do not stop other repos from syncing.
    ///
    /// - Returns: Dictionary of sync results keyed by repo ID (nil value = success, String = error message)
    @discardableResult
    func syncAll() async -> [UUID: String?] {
        if !isLoaded { await loadFromDisk() }

        var results: [UUID: String?] = [:]
        for repo in cachedRepos where repo.syncOnLaunch {
            do {
                try await sync(repo: repo)
                results[repo.id] = nil  // nil = success
            } catch {
                results[repo.id] = error.localizedDescription
            }
        }
        return results
    }

    /// Sync a single repository: clone if not yet cloned, pull if already cloned.
    ///
    /// After a successful sync, updates `lastSyncedAt` in the persisted config.
    ///
    /// - Parameter repo: The repository to sync
    /// - Throws: RepositoryError.cloneFailed or GitService.GitError
    func sync(repo: SkillRepository) async throws {
        if !isLoaded { await loadFromDisk() }

        // Ensure the base repos directory exists
        try createReposDirectoryIfNeeded()

        let httpAuthorization = try httpAuthorization(for: repo)

        let repoDir = URL(fileURLWithPath: repo.localPath)

        if repo.isCloned {
            // Repository already cloned — pull latest changes
            try await gitService.pull(repoDir: repoDir, httpAuthorization: httpAuthorization)
        } else {
            // First time — clone the repository
            // We clone directly into the target path (not a temp dir) since this is a persistent clone.
            // Git requires the target directory to NOT exist, so we just pass the final path.
            try await cloneDirectly(repo: repo, httpAuthorization: httpAuthorization)
        }

        // Update lastSyncedAt timestamp in persisted config
        if let idx = cachedRepos.firstIndex(where: { $0.id == repo.id }) {
            cachedRepos[idx].lastSyncedAt = Date()
            await saveToDisk()
        }
    }

    /// Scan a cloned repository for available Skills.
    ///
    /// 优先按仓库 `HEAD` 命中持久化缓存；只有 commit 变化或缓存缺失时，
    /// 才重新递归扫描并更新轻量索引。
    ///
    /// - Parameter repo: The repository to scan (must be cloned locally)
    /// - Returns: Array of discovered skills (empty if repo is not cloned)
    func scanSkills(in repo: SkillRepository) async -> [GitService.DiscoveredSkill] {
        let result = await scanSkillsResult(in: repo)
        return result.skills
    }

    /// Scan a cloned repository and return cache usage status for UI hints.
    func scanSkillsResult(in repo: SkillRepository) async -> ScanResult {
        guard repo.isCloned else {
            return ScanResult(skills: [], cacheStatus: .miss)
        }
        let repoDir = URL(fileURLWithPath: repo.localPath)

        let headCommit = try? await gitService.getCommitHash(in: repoDir)
        let isDirty = (try? await gitService.isWorkingTreeDirty(in: repoDir)) ?? true
        if !isDirty,
           let headCommit,
           let cached = await repositoryScanCache.getSkills(for: repo, headCommit: headCommit) {
            return ScanResult(skills: cached, cacheStatus: .hit)
        }

        let skills = await gitService.scanSkillsInRepo(
            repoDir: repoDir,
            includeHiddenPaths: repo.scanHiddenPaths
        )

        if !isDirty, let headCommit {
            try? await repositoryScanCache.saveSkills(skills, for: repo, headCommit: headCommit)
        }

        return ScanResult(
            skills: skills,
            cacheStatus: isDirty ? .bypassedDirtyWorkingTree : .miss
        )
    }

    /// Load the full content for a single discovered skill from the local clone.
    func loadSkillContent(in repo: SkillRepository, skillMDPath: String) async throws -> SkillMDParser.ParseResult {
        guard repo.isCloned else {
            throw RepositoryError.cloneFailed("Repository is not synced locally")
        }
        let repoDir = URL(fileURLWithPath: repo.localPath)
        return try await gitService.loadSkillContent(skillMDPath: skillMDPath, in: repoDir)
    }

    // MARK: - Private: Clone

    /// Clone a repository into its permanent location via GitService.
    ///
    /// **Why not call Process directly here?**
    /// `RepositoryManager` is a Swift `actor`. Calling `process.waitUntilExit()` (a
    /// synchronous blocking call) inside an actor would hold the actor's thread,
    /// preventing ALL other actor methods (including `scanSkills`) from running until
    /// the clone finishes. This causes the "Scanning repository…" spinner to hang
    /// because `scanSkills` is queued behind the blocking clone.
    ///
    /// **Solution**: delegate to `gitService.cloneRepo()`.
    /// Because `GitService` is a separate actor, `await gitService.cloneRepo(…)`
    /// *suspends* this actor's task and releases its thread — so `scanSkills` and
    /// other methods can run concurrently while git is cloning in the GitService actor.
    /// clone 成功后，会把临时目录移动到长期保存路径 `~/.skillsmaster/repos/<slug>/`。
    private func cloneDirectly(repo: SkillRepository, httpAuthorization: String?) async throws {
        // Full clone (not shallow) so `git pull` works later.
        // gitService.cloneRepo clones to /tmp/SkillsMaster-<UUID>/ first.
        // The `await` suspends RepositoryManager (releases the actor), allowing
        // scanSkills() and other calls to proceed while git is running.
        let tempDir = try await gitService.cloneRepo(
            repoURL: repo.repoURL,
            shallow: false,
            httpAuthorization: httpAuthorization
        )

        let targetURL = URL(fileURLWithPath: repo.localPath)
        let targetParentURL = targetURL.deletingLastPathComponent()

        // Ensure target parent directory exists before moving.
        // `FileManager.moveItem` does NOT create parent directories automatically
        // (different from `mkdir -p && mv` in shell), so we must prepare it explicitly.
        // This also protects against future base-path migrations.
        try FileManager.default.createDirectory(
            at: targetParentURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // If a previous partial clone left a directory behind, remove it first
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        // Move the temp clone to its permanent location atomically
        // (FileManager.moveItem is rename(2) when on the same filesystem as /tmp)
        do {
            try FileManager.default.moveItem(at: tempDir, to: targetURL)
        } catch {
            // Clean up temp dir if move fails
            try? FileManager.default.removeItem(at: tempDir)
            throw RepositoryError.cloneFailed("Failed to move cloned repository: \(error.localizedDescription)")
        }
    }

    private func httpAuthorization(for repo: SkillRepository) throws -> String? {
        guard repo.authType == .httpsToken else { return nil }

        guard let key = repo.credentialKey, !key.isEmpty else {
            throw RepositoryError.missingCredentials("Missing HTTPS token key for repository '\(repo.name)'")
        }
        guard let token = RepositoryCredentialStore.getToken(for: key), !token.isEmpty else {
            throw RepositoryError.missingCredentials("No access token found for repository '\(repo.name)'. Please reconfigure token in Settings.")
        }

        let trimmedUser = repo.httpUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = trimmedUser.isEmpty ? "git" : trimmedUser
        let raw = "\(username):\(token)"
        let basic = Data(raw.utf8).base64EncodedString()
        return "Authorization: Basic \(basic)"
    }

    // MARK: - Private: Persistence

    /// Read the config file from disk and populate cachedRepos.
    /// If the file doesn't exist yet, starts with an empty list.
    private func loadFromDisk() async {
        isLoaded = true
        let path = configFilePath

        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            cachedRepos = []
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(RepoConfig.self, from: data)
            var didRepairSlug = false
            cachedRepos = config.repositories.map { repo in
                var mutableRepo = repo
                if mutableRepo.normalizeLocalSlugIfNeeded() {
                    didRepairSlug = true
                }
                return mutableRepo
            }
            if didRepairSlug {
                await saveToDisk()
            }
        } catch {
            // Malformed config — reset to empty rather than crashing
            cachedRepos = []
        }
    }

    /// Write cachedRepos to disk atomically.
    ///
    /// Atomic write: write to a temp file first, then rename,
    /// so a crash mid-write doesn't corrupt the config.
    private func saveToDisk() async {
        let config = RepoConfig(version: 1, repositories: cachedRepos)

        do {
            let encoder = JSONEncoder()
            // Pretty-print for human readability (config is small, no perf concern)
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(config)

            let path = configFilePath

            // Ensure parent directory exists
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // Atomic write via temp file + rename
            let tempPath = path + ".tmp"
            FileManager.default.createFile(atPath: tempPath, contents: data)
            let targetURL = URL(fileURLWithPath: path)
            let tempURL = URL(fileURLWithPath: tempPath)

            if FileManager.default.fileExists(atPath: path) {
                // Existing file: replace atomically.
                _ = try FileManager.default.replaceItemAt(
                    targetURL,
                    withItemAt: tempURL
                )
            } else {
                // First write: move temp file to final path.
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
            }
        } catch {
            // Non-fatal: log but don't crash; the in-memory state remains consistent
        }
    }

    /// 确保 `~/.skillsmaster/repos/` 目录存在。
    private func createReposDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            atPath: reposBasePath,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

}
