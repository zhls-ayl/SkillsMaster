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
    @Environment(ToolPreferencesStore.self) private var toolPreferences

    /// `NavigationSplitView` 的栏位可见性状态。
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// 当前选中的 sidebar item。
    @State private var selectedSidebarItem: SidebarItem? = .allSkills

    /// 当前选中的 skill ID，用于驱动 detail 页面导航。
    @State private var selectedSkillID: String?

    /// All Skills 对应的 `ViewModel`。
    @State private var allSkillsVM: AllSkillsViewModel?

    /// Detail 对应的 `ViewModel`。
    @State private var detailVM: SkillDetailViewModel?

    /// F09：Skills.sh Browser 对应的 `ViewModel`。
    /// Created alongside other VMs in .task; manages leaderboard browsing and search
    @State private var skillsShVM: RegistryBrowserViewModel?
    /// ClawHub 浏览页面的 ViewModel。
    @State private var clawHubVM: ClawHubBrowserViewModel?
    /// SkillsHub 浏览页面的 ViewModel。
    @State private var skillsHubVM: SkillsHubBrowserViewModel?

    /// Repository ViewModels — one per configured repository, keyed by UUID.
    ///
    /// Dictionary lookup by UUID maps each `SidebarItem.repository(id)` selection to its VM.
    /// Created/refreshed in .task whenever the repositories list changes.
    /// Using [UUID: RepositoryBrowserViewModel] instead of [SkillRepository: VM] because
    /// SkillRepository can change (user renames it), but the UUID stays stable.
    @State private var repoVMs: [UUID: RepositoryBrowserViewModel] = [:]

    /// Agent root file browser ViewModels — one per file-manageable Agent.
    @State private var agentFilesVMs: [AgentType: AgentFilesViewModel] = [:]
    @State private var pendingNavigationAction: PendingNavigationAction?

    private enum PendingNavigationAction {
        case sidebar(SidebarItem?)
        case skill(String?)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // 左栏：sidebar navigation。
            // navigationSplitViewColumnWidth constrains sidebar width range,
            // preventing content from being clipped when sidebar is too narrow after window restoration
            SidebarView(selection: sidebarSelectionBinding)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            // 中栏：根据 sidebar selection 展示不同 content。
            // F09：当选中 “Skills.sh” 时，显示 `RegistryBrowserView` 而不是 `AllSkillsView`。
            if selectedSidebarItem == .skillsSh {
                // F09：skills.sh Browser，用于浏览和搜索 `skills.sh` catalog。
                if let vm = skillsShVM {
                    RegistryBrowserView(viewModel: vm)
                        // Skills.sh 页面需要更宽的中栏，以容纳 skill 信息和 install 按钮。
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if selectedSidebarItem == .clawHub {
                if let vm = clawHubVM {
                    ClawHubBrowserView(viewModel: vm)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if selectedSidebarItem == .skillsHub {
                if let vm = skillsHubVM {
                    SkillsHubBrowserView(viewModel: vm)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
                }
            } else if case .agentFiles(let agentType) = selectedSidebarItem,
                      let vm = agentFilesVMs[agentType] {
                AgentFilesBrowserView(viewModel: vm)
                    .id("agent-files-browser-\(agentType.rawValue)")
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
            } else if case .repository(let repoID) = selectedSidebarItem,
                      let vm = repoVMs[repoID] {
                // Repository browser：展示当前选中 repository 中的 skills。
                RepositoryBrowserView(viewModel: vm)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 600)
            } else {
                // 默认展示 All Skills 列表。
                if let vm = allSkillsVM {
                    AllSkillsView(
                        viewModel: vm,
                        selectedSkillID: skillSelectionBinding,
                        selectedAgentFilter: selectedSidebarItem?.agentFilter
                    )
                        // 约束中栏（skill list）的宽度范围，
                        // 避免初次打开时内容被过度压缩。
                        .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 450)
                }
            }
        } detail: {
            // 右栏：根据 sidebar selection 展示不同 detail view。
            if selectedSidebarItem == .skillsSh {
                // F09: Show registry skill detail when a registry skill is selected
                if let vm = skillsShVM, let skill = vm.selectedSkill {
                    RegistrySkillDetailView(
                        skill: skill,
                        isInstalled: vm.isInstalled(skill),
                        isInstalling: vm.isInstalling(skill),
                        onInstall: { vm.installSkill(skill) },
                        viewModel: vm
                    )
                } else {
                    EmptyStateView(
                        icon: "globe",
                        title: AppLocalization.string("Select a Skill"),
                        subtitle: AppLocalization.string("Please select a Skill from Skills.sh to view details.")
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
                        title: AppLocalization.string("Select a Skill"),
                        subtitle: AppLocalization.string("Please select a Skill from ClawHub to view details.")
                    )
                }
            } else if selectedSidebarItem == .skillsHub {
                if let vm = skillsHubVM, let skill = vm.selectedSkill {
                    SkillsHubSkillDetailView(
                        skill: skill,
                        isInstalled: vm.isInstalled(skill),
                        isInstalling: vm.isInstalling(skill),
                        onInstall: { vm.installSkill(skill) },
                        viewModel: vm
                    )
                } else {
                    EmptyStateView(
                        icon: "shippingbox.circle",
                        title: AppLocalization.string("Select a Skill"),
                        subtitle: AppLocalization.string("Please select a Skill from SkillsHub to view details.")
                    )
                }
            } else if case .agentFiles(let agentType) = selectedSidebarItem,
                      let vm = agentFilesVMs[agentType] {
                AgentFileDetailView(viewModel: vm)
                    .id("agent-files-detail-\(agentType.rawValue)")
            } else if case .repository = selectedSidebarItem {
                if case .repository(let repoID) = selectedSidebarItem,
                   let vm = repoVMs[repoID],
                   let skill = vm.selectedSkill {
                    RepositorySkillDetailView(
                        skill: skill,
                        repository: vm.repository,
                        viewModel: vm,
                        content: vm.selectedSkillContent,
                        isLoadingContent: vm.isLoadingSelectedSkillContent,
                        contentError: vm.selectedSkillContentError,
                        isInstalled: vm.isInstalled(skill),
                        onInstall: { vm.installSkill(skill) },
                        onLoadContent: { await vm.loadContent(for: skill) }
                    )
                } else {
                    EmptyStateView(
                        icon: "archivebox",
                        title: AppLocalization.string("Select a Skill"),
                        subtitle: AppLocalization.string("Please select a Skill from the Repository to view details.")
                    )
                }
            } else if let skillID = selectedSkillID, let vm = detailVM {
                SkillDetailView(
                    skillID: skillID,
                    viewModel: vm,
                    displayMode: SkillDetailView.DisplayMode.forSidebarSelection(selectedSidebarItem)
                )
                    // `.id(skillID)` 会强制 SwiftUI 在选中 skill 变化时销毁并重建 detail view，
                    // 而不是复用旧实例并走隐式的 cross-fade transition。
                    // 如果没有这行，`NavigationSplitView` 在过渡动画期间会短暂保留旧内容，
                    // 产生 1~3 秒左右的“陈旧内容”观感。
                    // 这个用法本质上类似 React 里的 `key`。
                    .id(skillID)
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: AppLocalization.string("Select a Skill"),
                    subtitle: AppLocalization.string("Please select a Skill from the list to view details.")
                )
            }
        }
        // `.task` 会在 `View` 首次出现时执行 async 任务，概念上类似 React 的 `useEffect([], ...)`。
        .task {
            allSkillsVM = AllSkillsViewModel(skillManager: skillManager)
            detailVM = SkillDetailViewModel(
                skillManager: skillManager,
                toolPreferences: toolPreferences
            )
            // F09: Initialize Skills.sh browser ViewModel
            skillsShVM = RegistryBrowserViewModel(skillManager: skillManager)
            clawHubVM = ClawHubBrowserViewModel(skillManager: skillManager)
            skillsHubVM = SkillsHubBrowserViewModel(skillManager: skillManager)
            // 先执行从旧路径（`~/.agents/`）到新路径（`~/.skillsmaster/`）的迁移。
            // 这一步必须发生在 `refresh()` 之前，否则 scanner 看不到新的 canonical 目录。
            MigrationManager.migrateIfNeeded()
            // 清理旧版 root-level GitHub 安装 bug 留下的残留 lock entry / cache / broken symlink。
            // 这是 best-effort maintenance，不应阻塞 app 启动。
            _ = try? await LegacyRootSkillArtifactCleaner().cleanup()
            await skillManager.refresh()
            // Build repoVMs for any repositories that were loaded during refresh
            rebuildRepoVMs()
            rebuildAgentFilesVMs()
            // Auto-check for updates on app launch (subject to 4-hour interval limit, not every launch requests GitHub API)
            await skillManager.checkForAppUpdate()
        }
        // Keep repoVMs in sync when the repositories list changes
        // (e.g., user adds or removes a repository in Settings)
        .onChange(of: skillManager.repositories) { _, _ in
            rebuildRepoVMs()
        }
        .onChange(of: skillManager.agents) { _, _ in
            rebuildAgentFilesVMs()
        }
        .confirmationDialog(
            AppLocalization.string("Unsaved Changes"),
            isPresented: Binding(
                get: { pendingNavigationAction != nil },
                set: { if !$0 { pendingNavigationAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Save")) {
                Task {
                    let didSave = await saveCurrentEditorForNavigation()
                    if didSave {
                        performPendingNavigationAction()
                    }
                }
            }
            Button(AppLocalization.string("Discard Changes"), role: .destructive) {
                discardCurrentEditorForNavigation()
                performPendingNavigationAction()
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {
                pendingNavigationAction = nil
            }
        } message: {
            Text(AppLocalization.string("The current editor has unsaved changes."))
        }
        .alert(
            item: Binding(
                get: { skillManager.translationPackPrompt },
                set: { skillManager.translationPackPrompt = $0 }
            )
        ) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text(AppLocalization.string("Got It"))) {
                    skillManager.dismissTranslationPackPrompt()
                },
                secondaryButton: .default(Text(AppLocalization.string("Don't show again"))) {
                    skillManager.dontShowTranslationPackPromptAgain()
                }
            )
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

    /// Create or remove AgentFilesViewModel instances to match currently available file-manageable Agents.
    private func rebuildAgentFilesVMs() {
        let supportedTypes = Set(
            skillManager.agents
                .filter(\.supportsRootFileManagement)
                .map(\.type)
        )

        for agentType in supportedTypes {
            if agentFilesVMs[agentType] == nil {
                agentFilesVMs[agentType] = AgentFilesViewModel(
                    agentType: agentType,
                    toolPreferences: toolPreferences
                )
            }
        }

        for agentType in agentFilesVMs.keys where !supportedTypes.contains(agentType) {
            agentFilesVMs.removeValue(forKey: agentType)
        }
    }

    private var sidebarSelectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { selectedSidebarItem },
            set: { newValue in
                requestSidebarSelection(newValue)
            }
        )
    }

    private var skillSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedSkillID },
            set: { newValue in
                requestSkillSelection(newValue)
            }
        )
    }

    private func requestSidebarSelection(_ newValue: SidebarItem?) {
        guard newValue != selectedSidebarItem else { return }

        if hasUnsavedChangesInCurrentEditor {
            pendingNavigationAction = .sidebar(newValue)
            return
        }

        discardCurrentEditorForNavigation()
        selectedSidebarItem = newValue
    }

    private func requestSkillSelection(_ newValue: String?) {
        guard newValue != selectedSkillID else { return }

        if hasUnsavedChangesInCurrentEditor {
            pendingNavigationAction = .skill(newValue)
            return
        }

        discardCurrentEditorForNavigation()
        selectedSkillID = newValue
    }

    private var hasUnsavedChangesInCurrentEditor: Bool {
        if let skillDetailViewModel = detailVM, skillDetailViewModel.hasUnsavedChangesInEditor {
            return true
        }

        if case .agentFiles(let agentType) = selectedSidebarItem,
           let agentFilesViewModel = agentFilesVMs[agentType],
           agentFilesViewModel.hasUnsavedChangesInEditor {
            return true
        }

        return false
    }

    private func saveCurrentEditorForNavigation() async -> Bool {
        if case .agentFiles(let agentType) = selectedSidebarItem,
           let agentFilesViewModel = agentFilesVMs[agentType],
           agentFilesViewModel.isEditingTextFile {
            return await agentFilesViewModel.saveCurrentEditorAndClose()
        }

        if let skillDetailViewModel = detailVM, skillDetailViewModel.isEditingTextFile {
            return await skillDetailViewModel.saveCurrentEditorAndClose()
        }

        return true
    }

    private func discardCurrentEditorForNavigation() {
        if case .agentFiles(let agentType) = selectedSidebarItem,
           let agentFilesViewModel = agentFilesVMs[agentType],
           agentFilesViewModel.isEditingTextFile {
            agentFilesViewModel.discardEditorForNavigation()
        }

        if let skillDetailViewModel = detailVM, skillDetailViewModel.isEditingTextFile {
            skillDetailViewModel.discardEditorForNavigation()
        }
    }

    private func performPendingNavigationAction() {
        switch pendingNavigationAction {
        case .sidebar(let sidebarItem):
            selectedSidebarItem = sidebarItem
        case .skill(let skillID):
            selectedSkillID = skillID
        case nil:
            break
        }

        pendingNavigationAction = nil
    }
}
