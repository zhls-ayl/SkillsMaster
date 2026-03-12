import SwiftUI

/// `ContentView` 是应用的 root view。
///
/// `NavigationSplitView` 是 macOS 常见的三栏布局，类似 Apple Mail：
/// - 左栏：sidebar navigation
/// - 中栏：content list
/// - 右栏：detail pane
///
/// 这里通过 `@Environment` 从 `View` tree 中读取注入的依赖，
/// `SkillManager` 由 `SkillsMasterApp.swift` 中的 `.environment()` 统一注入。
struct ContentView: View {

    @Environment(SkillManager.self) private var skillManager

    /// `NavigationSplitView` 的栏位可见性状态。
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// 当前选中的 sidebar item。
    @State private var selectedSidebarItem: SidebarItem? = .dashboard

    /// 当前选中的 skill ID，用于驱动 detail 页面导航。
    @State private var selectedSkillID: String?

    /// Dashboard 对应的 `ViewModel`。
    @State private var dashboardVM: DashboardViewModel?

    /// Detail 对应的 `ViewModel`。
    @State private var detailVM: SkillDetailViewModel?

    /// F09：Registry Browser 对应的 `ViewModel`。
    /// Created alongside other VMs in .task; manages leaderboard browsing and search
    @State private var registryVM: RegistryBrowserViewModel?
    /// ClawHub 浏览页面的 ViewModel。
    @State private var clawHubVM: ClawHubBrowserViewModel?

    /// Custom repository ViewModels — one per configured repository, keyed by UUID.
    ///
    /// Dictionary lookup by UUID maps each `SidebarItem.customRepo(id)` selection to its VM.
    /// Created/refreshed in .task whenever the repositories list changes.
    /// Using [UUID: RepositoryBrowserViewModel] instead of [SkillRepository: VM] because
    /// SkillRepository can change (user renames it), but the UUID stays stable.
    @State private var repoVMs: [UUID: RepositoryBrowserViewModel] = [:]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 左栏：sidebar navigation。
            // navigationSplitViewColumnWidth constrains sidebar width range,
            // preventing content from being clipped when sidebar is too narrow after window restoration
            SidebarView(selection: $selectedSidebarItem)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            // 中栏：根据 sidebar selection 展示不同 content。
            // F09：当选中 “Registry” 时，显示 `RegistryBrowserView` 而不是 `DashboardView`。
            if selectedSidebarItem == .registry {
                // F09：Registry Browser，用于浏览和搜索 `skills.sh` catalog。
                if let vm = registryVM {
                    RegistryBrowserView(viewModel: vm)
                        // Registry 页面需要更宽的中栏，以容纳 skill 信息和 install 按钮。
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if selectedSidebarItem == .clawHub {
                if let vm = clawHubVM {
                    ClawHubBrowserView(viewModel: vm)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if case .customRepo(let repoID) = selectedSidebarItem,
                      let vm = repoVMs[repoID] {
                // Custom repository browser：展示当前选中 repository 中的 skills。
                RepositoryBrowserView(viewModel: vm)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            } else {
                // 默认展示 skill dashboard 列表。
                if let vm = dashboardVM {
                    DashboardView(
                        viewModel: vm,
                        selectedSkillID: $selectedSkillID,
                        selectedAgentFilter: selectedSidebarItem?.agentFilter
                    )
                        // 约束中栏（skill list）的宽度范围，
                        // 避免初次打开时内容被过度压缩。
                        .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 450)
                }
            }
        } detail: {
            // 右栏：根据 sidebar selection 展示不同 detail view。
            if selectedSidebarItem == .registry {
                // F09: Show registry skill detail when a registry skill is selected
                if let vm = registryVM, let skill = vm.selectedSkill {
                    RegistrySkillDetailView(
                        skill: skill,
                        isInstalled: vm.isInstalled(skill),
                        onInstall: { vm.installSkill(skill) },
                        viewModel: vm
                    )
                } else {
                    EmptyStateView(
                        icon: "globe",
                        title: "请选择 Skill",
                        subtitle: "请从 Registry 中选择一个 Skill 查看详情"
                    )
                }
            } else if selectedSidebarItem == .clawHub {
                if let vm = clawHubVM, let skill = vm.selectedSkill {
                    ClawHubSkillDetailView(
                        skill: skill,
                        isInstalled: vm.isInstalled(skill),
                        isInstalling: vm.isInstalling(skill),
                        onInstall: { vm.installSkill(skill) },
                        viewModel: vm
                    )
                } else {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "请选择 Skill",
                        subtitle: "请从 ClawHub 中选择一个 Skill 查看详情"
                    )
                }
            } else if case .customRepo = selectedSidebarItem {
                if case .customRepo(let repoID) = selectedSidebarItem,
                   let vm = repoVMs[repoID],
                   let skill = vm.selectedSkill {
                    RepositorySkillDetailView(
                        skill: skill,
                        repository: vm.repository,
                        content: vm.selectedSkillContent,
                        isLoadingContent: vm.isLoadingSelectedSkillContent,
                        contentError: vm.selectedSkillContentError,
                        isInstalled: vm.isInstalled(skill),
                        canInstall: vm.canInstallFromLocal,
                        installDisabledReason: vm.installDisabledReason,
                        onInstall: { vm.installSkill(skill) },
                        onLoadContent: { await vm.loadContent(for: skill) }
                    )
                } else {
                    EmptyStateView(
                        icon: "archivebox",
                        title: "请选择 Skill",
                        subtitle: "请从 Repository 中选择一个 Skill 查看详情"
                    )
                }
            } else if let skillID = selectedSkillID, let vm = detailVM {
                SkillDetailView(skillID: skillID, viewModel: vm)
                    // `.id(skillID)` 会强制 SwiftUI 在选中 skill 变化时销毁并重建 detail view，
                    // 而不是复用旧实例并走隐式的 cross-fade transition。
                    // 如果没有这行，`NavigationSplitView` 在过渡动画期间会短暂保留旧内容，
                    // 产生 1~3 秒左右的“陈旧内容”观感。
                    // 这个用法本质上类似 React 里的 `key`。
                    .id(skillID)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "请选择 Skill",
                    subtitle: "请从列表中选择一个 Skill 查看详情"
                )
            }
        }
        // `.task` 会在 `View` 首次出现时执行 async 任务，概念上类似 React 的 `useEffect([], ...)`。
        .task {
            dashboardVM = DashboardViewModel(skillManager: skillManager)
            detailVM = SkillDetailViewModel(skillManager: skillManager)
            // F09: Initialize registry browser ViewModel
            registryVM = RegistryBrowserViewModel(skillManager: skillManager)
            clawHubVM = ClawHubBrowserViewModel(skillManager: skillManager)
            // 先执行从旧路径（`~/.agents/`）到新路径（`~/.skillsmaster/`）的迁移。
            // 这一步必须发生在 `refresh()` 之前，否则 scanner 看不到新的 canonical 目录。
            MigrationManager.migrateIfNeeded()
            await skillManager.refresh()
            // Build repoVMs for any repositories that were loaded during refresh
            rebuildRepoVMs()
            // Auto-check for updates on app launch (subject to 4-hour interval limit, not every launch requests GitHub API)
            await skillManager.checkForAppUpdate()
        }
        // Keep repoVMs in sync when the repositories list changes
        // (e.g., user adds or removes a repository in Settings)
        .onChange(of: skillManager.repositories) { _, _ in
            rebuildRepoVMs()
        }
    }

    // MARK: - Private Helpers

    /// Create or update the repoVMs dictionary to match the current repositories list.
    ///
    /// - Adds a new RepositoryBrowserViewModel for any newly added repository
    /// - Removes VMs for repositories that were deleted
    /// - Keeps existing VMs for unchanged repositories (preserves their loaded state)
    ///
    /// Called on initial app load and whenever skillManager.repositories changes.
    private func rebuildRepoVMs() {
        // Add VMs for new repos
        for repo in skillManager.repositories {
            if let vm = repoVMs[repo.id] {
                // Keep existing VM state, but refresh repo metadata snapshot.
                vm.updateRepository(repo)
            } else {
                repoVMs[repo.id] = RepositoryBrowserViewModel(
                    repository: repo,
                    skillManager: skillManager
                )
            }
        }

        // Remove VMs for deleted repos
        let currentIDs = Set(skillManager.repositories.map(\.id))
        for id in repoVMs.keys where !currentIDs.contains(id) {
            repoVMs.removeValue(forKey: id)
        }
    }
}
