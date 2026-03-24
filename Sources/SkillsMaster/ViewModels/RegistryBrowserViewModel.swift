import Foundation

/// `RegistryBrowserViewModel` 负责 F09 Registry Browser 的页面状态。
///
/// 它主要处理三类场景：
/// 1. **Leaderboard browsing**：展示 all-time / trending / hot 列表
/// 2. **Search**：对 `skills.sh` 执行带 debounce 的搜索
/// 3. **Install**：为选中的 registry skill 触发安装流程
///
/// `@Observable` 会自动追踪属性变化并驱动 SwiftUI 刷新，
/// `@MainActor` 则保证所有 UI state 更新都发生在 main thread。
@MainActor
@Observable
final class RegistryBrowserViewModel {

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - State

    /// 当前选中的 leaderboard category tab（All Time / Trending / Hot）。
    var selectedCategory: SkillRegistryService.LeaderboardCategory = .allTime

    /// 用户输入的搜索文本（为空时显示 leaderboard，非空时显示 search result）。
    var searchText = ""

    /// 当前视图中展示的 skills（可能来自 leaderboard，也可能来自 search result）。
    var displayedSkills: [RegistrySkill] = []

    /// 当前是否处于 loading 状态（用于驱动 UI spinner）。
    var isLoading = false

    /// 触底加载下一批时的 loading 状态。
    var isLoadingMore = false

    /// 需要展示的错误信息（`nil` 表示没有错误）。
    var errorMessage: String?

    /// 仅用于底部分页加载阶段的错误提示。
    var loadMoreErrorMessage: String?

    /// 当前是否还有更多列表结果可加载。
    private(set) var hasMoreResults = true

    /// leaderboard scraping 是否失败。
    /// 之所以单独保留这个状态，是为了和 `errorMessage` 区分不同的 UI 呈现方式。
    var leaderboardUnavailable = false

    /// 记录“已安装 skill ID → source repo”的映射，数据来自 `lock file`。
    /// 这样在显示 “Installed” 标记时，就能基于 source 做精确匹配，
    /// 避免两个 `skillId` 相同但 repo 不同的 registry 项被错误合并。
    private var installedSkillSources: [String: String] = [:]

    /// 没有 source 追踪信息的已安装 skill ID 集合（通常表示没有 `lockEntry`）。
    /// 这里保留按 `skillId` 回退匹配的逻辑，用于兼容手动安装、未经过 registry flow 的旧数据。
    private var installedSkillIDsNoSource: Set<String> = []

    /// 详情页内联安装的目标 Agent 选择。
    var selectedTargetAgents: Set<AgentType> = []

    /// 当前正在执行安装的 registry skill ID。
    var installingSkillID: String?

    /// 安装阶段展示在主按钮上的状态文案。
    var installingStatusMessage: String?

    /// Alert 弹窗提示。
    var notice: Notice?

    // MARK: - Skill Content State

    /// 当前选中 registry skill 的已解析 `SKILL.md` 内容。
    ///
    /// 成功拉取并解析后这里会有值。
    /// 其中同时包含 metadata（如 author、version、license）和 Markdown 正文。
    /// 当用户切换到新的 skill 时，会先重置为 `nil`，再加载新内容。
    var fetchedContent: SkillMDParser.ParseResult?

    /// 当前选中 skill 的 `SKILL.md` 是否正在拉取。
    ///
    /// 这个状态会驱动 detail view 中的 `ProgressView` spinner。
    var isLoadingContent = false

    /// `SKILL.md` 拉取失败时的错误信息（`nil` 表示没有错误）。
    ///
    /// 会显示在 detail view 中，并配合兜底的 “View on skills.sh” 链接一起出现。
    /// 常见原因包括：repo 中不存在 `SKILL.md`、network timeout、内容不是 UTF-8。
    var contentError: String?

    /// 当前选中的 registry skill ID，用于驱动 detail pane。
    ///
    /// 当用户在列表里点击某个 skill 时，这里会被设置为对应的 `id`，
    /// detail pane 随后展示 `RegistrySkillDetailView`。
    var selectedSkillID: String? {
        didSet {
            guard oldValue != selectedSkillID else { return }
            syncSelectedTargetAgentsForCurrentSelection()
        }
    }

    /// 便捷属性：返回当前选中的 `RegistrySkill`。
    ///
    /// 根据 `selectedSkillID` 从 `displayedSkills` 中查找当前选中的 skill。
    /// 如果还没有选中项，或者 ID 无法匹配到任何结果，就返回 `nil`。
    var selectedSkill: RegistrySkill? {
        guard let id = selectedSkillID else { return nil }
        return displayedSkills.first { $0.id == id }
    }

    /// 当前是否处于 search mode。
    /// 这是一个 computed property，不需要单独存储，直接由 `searchText` 推导。
    var isSearchActive: Bool {
        normalizedSearchText != nil
    }

    var targetAgentTypes: [AgentType] {
        AgentType.displayNameLengthSortedCases
    }

    // MARK: - Dependencies

    /// 用于 API 调用和 HTML scraping 的 registry service。
    private let registryService: any SkillRegistryServiceProtocol

    /// 用于从 GitHub raw URL 下载 `SKILL.md` 的 content fetcher。
    ///
    /// 它和 `registryService` 一样采用 `actor` 模式维护 thread-safe cache，
    /// 并支持 `main → master` 的 branch fallback。
    private let contentFetcher = SkillContentFetcher()

    /// `SkillManager` 引用，用于判断安装状态并触发安装流程。
    private let skillManager: SkillManager
    private let gitService = GitService()

    // MARK: - Search Debounce

    /// 用于 search-as-you-type 的 debounce task。
    ///
    /// 当用户快速输入时，会取消上一个搜索任务并创建新的任务，
    /// 只有最后一次输入会在 300ms 延迟后真正触发 API 调用。
    /// `Task<Void, Never>` 表示这是一个不返回值、也不会向外抛错的 async task。
    private var searchTask: Task<Void, Never>?
    private let pageSize = 50
    private let loadMoreThreshold = 5
    private var currentLimit = 50
    private var allLoadedSkills: [RegistrySkill] = []
    private var listRequestVersion = 0

    // MARK: - Init

    /// 通过依赖注入初始化 `SkillManager`。
    ///
    /// `SkillManager` 来自上层 `View` tree（由 `ContentView` 继续向下传递），
    /// `ViewModel` 自己不会新建一份实例。
    init(
        skillManager: SkillManager,
        registryService: any SkillRegistryServiceProtocol = SkillRegistryService()
    ) {
        self.skillManager = skillManager
        self.registryService = registryService
    }

    // MARK: - Lifecycle

    /// 在视图首次出现时调用（由 SwiftUI 的 `.task` 触发）。
    ///
    /// 可以把它理解成“页面首次展示时执行的 async 初始化逻辑”。
    func onAppear() async {
        syncInstalledSkills()
        await reloadCurrentList()
    }

    /// 从 `SkillManager` 同步已安装 skill 数据，用于 source-aware 的 “Installed” 标记。
    ///
    /// 这里会构建两份索引：
    /// - `installedSkillSources`：记录带 `lockEntry` 的 skill 对应 source repo
    /// - `installedSkillIDsNoSource`：记录没有 `lockEntry` 的手动安装 skill
    ///
    /// 这样即使两个 registry skill 拥有相同 `skillId`，只要 source 不同，也不会被同时标记为已安装。
    func syncInstalledSkills() {
        var sources: [String: String] = [:]
        var noSource: Set<String> = []
        for skill in skillManager.skills {
            // 如果 skill 的 `lockEntry` 带有 source（例如 `owner/repo`），
            // 就记录下来，用于后续的精确 source 匹配。
            if let source = skill.lockEntry?.source {
                sources[skill.id] = source
            } else {
                // 没有 `lockEntry` 通常意味着它是手动安装的，不来自 registry。
                // 这里保留按 `skillId` 回退匹配的兼容逻辑。
                noSource.insert(skill.id)
            }
        }
        installedSkillSources = sources
        installedSkillIDsNoSource = noSource
    }

    // MARK: - Leaderboard

    /// 加载当前 category 的 leaderboard 数据。
    ///
    /// 数据通过 `SkillRegistryService` 从 `skills.sh` 页面抓取。
    /// 如果失败，会设置 `leaderboardUnavailable`，让界面退化为搜索提示。
    func loadLeaderboard() async {
        guard !isSearchActive else { return }
        await reloadCurrentList()
    }

    /// 切换 leaderboard category tab，并重新加载数据。
    ///
    /// 用户点击 `All Time / Trending / Hot` 时会调用这里。
    /// 由于 service 层带有 5 分钟 cache，因此首轮加载之后切换 tab 会比较快。
    func selectCategory(_ category: SkillRegistryService.LeaderboardCategory) async {
        selectedCategory = category
        await reloadCurrentList()
    }

    /// 刷新当前数据（清空 cache 后重新加载）。
    ///
    /// 由 toolbar 的刷新按钮触发，用来强制从 `skills.sh` 拉取最新数据。
    func refresh() async {
        await registryService.clearCache()
        await reloadCurrentList()
    }

    // MARK: - Search

    /// 在 `searchText` 变化时触发（带 debounce）。
    ///
    /// 当前实现的流程是：
    /// 1. 取消任何尚未完成的搜索任务
    /// 2. 如果搜索词为空，就切回 leaderboard
    /// 3. 否则等待 300ms，再执行真正的搜索
    ///
    /// 这样可以避免用户快速输入时触发过多 API 调用。
    func onSearchTextChanged() {
        // 取消上一个尚未完成的搜索任务。
        searchTask?.cancel()

        if normalizedSearchText == nil {
            // 用户清空了搜索框，切回 leaderboard。
            Task { await reloadCurrentList() }
            return
        }

        // 创建新的 debounce 搜索任务。
        searchTask = Task {
            // 等待 300ms；如果用户继续输入，这个任务会被取消并由新任务替代。
            try? await Task.sleep(for: .milliseconds(300))

            // 检查任务在等待期间是否已经被取消（通常表示用户又输入了新内容）。
            guard !Task.isCancelled else { return }

            await reloadCurrentList()
        }
    }

    func loadMoreIfNeeded(after skillID: String) async {
        guard shouldLoadMore(after: skillID) else { return }
        await loadMore()
    }

    func retryLoadMore() async {
        guard !isLoading else { return }
        await loadMore()
    }

    // MARK: - Install

    func installSkill(_ registrySkill: RegistrySkill) {
        guard installingSkillID == nil else { return }
        guard !selectedTargetAgents.isEmpty else {
            notice = Notice(title: "无法安装", message: "请至少选择一个目标 Agent。")
            return
        }

        Task { await performInstall(registrySkill) }
    }

    /// 判断某个 registry skill 是否已经在本地安装。
    ///
    /// 这里采用 source-aware 匹配，避免多个不同 repository 里的同名 `skillId` 产生误判：
    /// 1. 如果本地 skill 的 `skillId` 和 source 都匹配，则返回 `true`
    /// 2. 如果本地 skill 没有 `lockEntry`，则回退到仅按 `skillId` 匹配
    /// 3. 其他情况返回 `false`
    func isInstalled(_ registrySkill: RegistrySkill) -> Bool {
        matchingInstalledSkill(for: registrySkill) != nil
    }

    func isInstalling(_ registrySkill: RegistrySkill) -> Bool {
        installingSkillID == registrySkill.id
    }

    func toggleTargetAgent(_ agent: AgentType) {
        if selectedTargetAgents.contains(agent) {
            selectedTargetAgents.remove(agent)
        } else {
            selectedTargetAgents.insert(agent)
        }
    }

    func isAgentDetected(_ agent: AgentType) -> Bool {
        skillManager.agents.first { $0.type == agent }?.supportsRootFileManagement == true
    }

    func targetSelectionSummary() -> String {
        let count = selectedTargetAgents.count
        if count == 0 {
            return "未选择 Agent"
        }
        return count == 1 ? "1 个 Agent 已选中" : "\(count) 个 Agent 已选中"
    }

    func detailInstallButtonTitle(for registrySkill: RegistrySkill) -> String {
        if isInstalling(registrySkill) {
            return installingStatusMessage ?? "Installing..."
        }
        return installAction(for: registrySkill).title
    }

    func detailInstallButtonSystemImage(for registrySkill: RegistrySkill) -> String {
        installAction(for: registrySkill).systemImage
    }

    // MARK: - Pagination / List Loading

    private func reloadCurrentList() async {
        currentLimit = pageSize
        hasMoreResults = true
        isLoadingMore = false
        loadMoreErrorMessage = nil
        await fetchCurrentList(reset: true)
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMoreResults else { return }

        // Leaderboard 模式直接在本地展开下一批，不重复发请求。
        if normalizedSearchText == nil {
            currentLimit += pageSize
            applyVisibleSkills()
            return
        }

        currentLimit += pageSize
        await fetchCurrentList(reset: false)
    }

    private func fetchCurrentList(reset: Bool) async {
        listRequestVersion += 1
        let requestVersion = listRequestVersion

        if reset {
            isLoading = true
            errorMessage = nil
            leaderboardUnavailable = false
        } else {
            isLoadingMore = true
            loadMoreErrorMessage = nil
        }

        do {
            if let query = normalizedSearchText {
                let skills = try await registryService.search(query: query, limit: currentLimit)
                guard requestVersion == listRequestVersion else { return }
                allLoadedSkills = skills
                applyVisibleSkills()
                hasMoreResults = !skills.isEmpty && skills.count >= currentLimit
                leaderboardUnavailable = false
            } else {
                let skills = try await registryService.fetchLeaderboard(category: selectedCategory)
                guard requestVersion == listRequestVersion else { return }
                allLoadedSkills = skills
                applyVisibleSkills()
                hasMoreResults = displayedSkills.count < allLoadedSkills.count
                leaderboardUnavailable = false
            }
        } catch {
            guard requestVersion == listRequestVersion else { return }

            if reset {
                allLoadedSkills = []
                displayedSkills = []
                if normalizedSearchText == nil {
                    errorMessage = "无法加载排行榜，请改用搜索。"
                    leaderboardUnavailable = true
                } else {
                    errorMessage = "搜索失败：\(error.localizedDescription)"
                    leaderboardUnavailable = false
                }
            } else {
                currentLimit = max(pageSize, currentLimit - pageSize)
                loadMoreErrorMessage = error.localizedDescription
            }
        }

        guard requestVersion == listRequestVersion else { return }
        if reset {
            isLoading = false
        } else {
            isLoadingMore = false
        }
    }

    private func applyVisibleSkills() {
        displayedSkills = Array(allLoadedSkills.prefix(currentLimit))
        if let selectedSkillID, displayedSkills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        selectedSkillID = displayedSkills.first?.id
    }

    private var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldLoadMore(after skillID: String) -> Bool {
        guard hasMoreResults, !isLoading, !isLoadingMore, loadMoreErrorMessage == nil else {
            return false
        }
        guard let index = displayedSkills.firstIndex(where: { $0.id == skillID }) else {
            return false
        }
        let triggerIndex = max(displayedSkills.count - loadMoreThreshold, 0)
        return index >= triggerIndex
    }

    private func performInstall(_ registrySkill: RegistrySkill) async {
        let action = installAction(for: registrySkill)
        let targetAgents = selectedTargetAgents
        installingSkillID = registrySkill.id
        installingStatusMessage = "Validating repository..."
        defer {
            installingSkillID = nil
            installingStatusMessage = nil
        }

        do {
            let (repoURL, repoSource) = try GitService.normalizeRepoURL(registrySkill.source)

            installingStatusMessage = "Checking git..."
            let gitAvailable = await gitService.checkGitAvailable()
            guard gitAvailable else {
                throw GitService.GitError.gitNotInstalled
            }

            installingStatusMessage = "Cloning repository..."
            let repoDir = try await gitService.shallowClone(repoURL: repoURL)
            defer {
                Task { await self.gitService.cleanupTempDirectory(repoDir) }
            }

            installingStatusMessage = "Scanning skills..."
            let discoveredSkills = await gitService.scanSkillsInRepo(repoDir: repoDir)
            guard let discoveredSkill = discoveredSkills.first(where: { $0.id == registrySkill.skillId }) else {
                throw SkillManager.ImportError.directoryNotFound(
                    "Skill '\(registrySkill.skillId)' not found in repository."
                )
            }

            installingStatusMessage = "Installing..."
            try await skillManager.installSkill(
                from: repoDir,
                skill: discoveredSkill,
                repoSource: repoSource,
                repoURL: repoURL,
                sourceType: "github",
                targetAgents: targetAgents
            )

            syncInstalledSkills()
            notice = Notice(
                title: action.completionTitle,
                message: "\(registrySkill.name) 已安装到 \(targetAgents.count) 个 Agent。"
            )
        } catch {
            notice = Notice(title: "Installation Failed", message: error.localizedDescription)
        }
    }

    private func installAction(for registrySkill: RegistrySkill) -> MarketplaceInstallAction {
        let fallback: MarketplaceInstallAction = isInstalled(registrySkill) ? .reinstall : .install
        return MarketplaceInstallAction.resolve(
            selectedAgents: selectedTargetAgents,
            directInstalledAgents: directInstalledAgents(for: registrySkill),
            fallbackWhenSelectionEmpty: fallback
        )
    }

    private func directInstalledAgents(for registrySkill: RegistrySkill) -> Set<AgentType> {
        guard let installedSkill = matchingInstalledSkill(for: registrySkill) else {
            return []
        }

        return Set(
            installedSkill.installations
                .filter { !$0.isInherited }
                .map(\.agentType)
        )
    }

    private func matchingInstalledSkill(for registrySkill: RegistrySkill) -> Skill? {
        if let installedSource = installedSkillSources[registrySkill.skillId],
           installedSource == registrySkill.source {
            return skillManager.skills.first {
                $0.id == registrySkill.skillId && $0.lockEntry?.source == registrySkill.source
            }
        }

        if installedSkillIDsNoSource.contains(registrySkill.skillId) {
            return skillManager.skills.first {
                $0.id == registrySkill.skillId && $0.lockEntry == nil
            }
        }

        return nil
    }

    private func syncSelectedTargetAgentsForCurrentSelection() {
        guard let selectedSkill else {
            selectedTargetAgents.removeAll()
            return
        }
        selectedTargetAgents = directInstalledAgents(for: selectedSkill)
    }

    // MARK: - Skill Content Loading

    /// Load the full SKILL.md content for a registry skill from GitHub
    ///
    /// Called from the detail view's `.task(id:)` modifier — auto-cancels when the user
    /// selects a different skill. This prevents stale content from appearing.
    ///
    /// Flow:
    /// 1. Reset state (clear previous content/error, show loading spinner)
    /// 2. Fetch raw SKILL.md from GitHub via `SkillContentFetcher`
    /// 3. Parse with `SkillMDParser.parse(content:)` to extract metadata + markdown body
    /// 4. Guard against stale updates: only apply if the selected skill hasn't changed
    ///
    /// **Fallback for SKILL.md without frontmatter**: If the content doesn't have YAML frontmatter
    /// (no `---` delimiters), we treat the entire content as the markdown body with empty metadata.
    ///
    /// - Parameter skill: The registry skill whose SKILL.md to fetch
    func loadSkillContent(for skill: RegistrySkill) async {
        // Reset state for new content load
        fetchedContent = nil
        contentError = nil
        isLoadingContent = true

        // Capture the skill ID to guard against stale updates.
        // If the user clicks a different skill while this fetch is in-flight,
        // `selectedSkillID` will change. We check it after the await to discard stale results.
        let targetSkillID = skill.id

        do {
            // Fetch raw SKILL.md content from GitHub
            // SkillContentFetcher tries main branch first, then master, with 10-min cache
            let rawContent = try await contentFetcher.fetchContent(
                source: skill.source,
                skillId: skill.skillId
            )

            // Guard: discard result if user selected a different skill while we were fetching.
            // This is the Swift async equivalent of checking "is this still the current request?"
            // similar to checking a request ID in React's useEffect cleanup.
            guard selectedSkillID == targetSkillID else { return }

            // Parse the SKILL.md content into metadata + markdown body
            do {
                let result = try SkillMDParser.parse(content: rawContent)
                fetchedContent = result
            } catch {
                // Fallback: if parsing fails (e.g., no YAML frontmatter),
                // treat the entire content as the markdown body.
                // Create a minimal metadata with the skill name from the registry.
                let fallbackMetadata = SkillMetadata(
                    name: skill.name,
                    description: ""
                )
                fetchedContent = SkillMDParser.ParseResult(
                    metadata: fallbackMetadata,
                    frontmatterText: "",
                    markdownBody: rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch {
            // Guard: discard error if user selected a different skill
            guard selectedSkillID == targetSkillID else { return }
            contentError = error.localizedDescription
        }

        isLoadingContent = false
    }
}
