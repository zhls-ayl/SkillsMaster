import SwiftUI

/// `SkillDetailView` 是 F03 对应的 skill 详情页。
///
/// 页面会展示完整的 skill 信息，包括：
/// - 基础信息（name、description、author、version）
/// - Agent assignment 状态（可切换）
/// - Markdown 正文
/// - lock file 信息
/// - 操作按钮（edit、delete、open in Finder / Terminal）
struct SkillDetailView: View {

    enum DisplayMode: Equatable {
        case management
        case contentOnly

        var showsManagementUI: Bool {
            self == .management
        }

        var translationScope: SkillTranslationScope {
            switch self {
            case .management:
                .installed
            case .contentOnly:
                .agents
            }
        }

        static func forSidebarSelection(_ selection: SidebarItem?) -> Self {
            if case .skillsByAgent = selection {
                return .contentOnly
            }
            return .management
        }
    }

    let skillID: String
    @Bindable var viewModel: SkillDetailViewModel
    let displayMode: DisplayMode

    /// 复制路径按钮的反馈状态：为 `true` 时显示绿色勾选，1.5 秒后自动恢复。
    @State private var pathCopied = false

    private var headerDescriptionText: String {
        guard let skill = viewModel.skill(id: skillID) else { return "" }
        return FrontmatterDisplay.value(for: "description", in: skill.frontmatterText)
            ?? skill.metadata.description
    }

    private var extraFrontmatterFields: [FrontmatterField] {
        guard let skill = viewModel.skill(id: skillID) else { return [] }
        return FrontmatterDisplay.extraFields(
            from: skill.frontmatterText,
            excluding: ["name", "description", "license"]
        )
    }

    private var shouldShowSkillMetadata: Bool {
        guard let skill = viewModel.skill(id: skillID) else { return false }
        return skill.metadata.author != nil
            || skill.metadata.version != nil
            || skill.metadata.license != nil
            || !extraFrontmatterFields.isEmpty
    }

    var body: some View {
        if let editorViewModel = viewModel.editorViewModel {
            TextFileEditorView(
                viewModel: editorViewModel,
                onSave: {
                    _ = await viewModel.saveCurrentEditorAndClose()
                },
                onCancel: {
                    viewModel.requestCloseEditor()
                }
            )
            .confirmationDialog(
                "未保存修改",
                isPresented: Binding(
                    get: { viewModel.pendingEditorAction != nil },
                    set: { if !$0 { viewModel.cancelPendingEditorAction() } }
                ),
                titleVisibility: .visible
            ) {
                Button("保存") {
                    Task { _ = await viewModel.saveCurrentEditorAndClose() }
                }
                Button("放弃修改", role: .destructive) {
                    viewModel.discardPendingEditorAction()
                }
                Button("取消", role: .cancel) {
                    viewModel.cancelPendingEditorAction()
                }
            } message: {
                Text("当前 `SKILL.md` 有未保存修改。")
            }
        } else if let skill = viewModel.skill(id: skillID) {
            // 这里相当于 SwiftUI 版的 `guard let`：如果 skill 不存在，就直接展示 empty state。
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 头部信息区。
                    headerSection(skill)

                    if shouldShowSkillMetadata {
                        Divider()
                        skillMetadataSection(skill)
                    }

                    if displayMode.showsManagementUI {
                        // Package 信息区（含 update 状态），进入详情页后优先展示。
                        // 如果存在 `lockEntry`，展示完整 package 信息；否则展示手动关联 repo 的 UI。
                        Divider()
                        if let lockEntry = skill.lockEntry {
                            lockFileSection(skill, lockEntry)
                        } else {
                            linkToRepoSection(skill)
                        }

                        Divider()

                        // Agent assignment 区域。
                        agentAssignmentSection(skill)
                    }

                    Divider()

                    // Markdown 正文区域。
                    markdownSection(skill)
                }
                .padding()
            }
            .navigationTitle(skill.displayName)
            .task(id: skill.id) {
                viewModel.resetManualTranslationIfNeeded(for: skill.id)
            }
            .toolbar {
                ToolbarItemGroup {
                    if displayMode.showsManagementUI {
                        // 在 Finder 中定位。
                        Button {
                            viewModel.revealInFinder(skill: skill)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("在 Finder 中显示")

                        // 在 Terminal 中打开。
                        Button {
                            viewModel.openInTerminal(skill: skill)
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .help("在 Terminal 中打开")
                    }

                    Button {
                        viewModel.requestManualTranslation(for: skill.id)
                    } label: {
                        Image(systemName: "translate")
                    }
                    .help("翻译当前 Skill")
                    .disabled(!viewModel.canRequestManualTranslation(for: skill.id))

                    if displayMode.showsManagementUI {
                        // 编辑按钮。
                        Button {
                            viewModel.startEditing(skill: skill)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help("Edit SKILL.md")

                        Button {
                            viewModel.openInExternalEditor(skill: skill)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .help("在外置编辑器中打开 SKILL.md")
                    }
                } 
            }
        } else {
            EmptyStateView(
                icon: "questionmark.circle",
                title: "找不到 Skill",
                subtitle: "当前选中的 Skill 可能已被删除"
            )
        }
    }

    // MARK: - Sections

    /// 头部信息区。
    @ViewBuilder
    private func headerSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.displayName)
                    .font(.title)
                    .fontWeight(.bold)

                ScopeBadge(scope: skill.scope)
            }

            if !headerDescriptionText.isEmpty {
                SkillDescriptionText(
                    text: headerDescriptionText,
                    font: .body,
                    isSelectable: true
                )
            }
        }
    }

    @ViewBuilder
    private func skillMetadataSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skill Metadata")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let author = skill.metadata.author {
                    GridRow {
                        Text("Author").foregroundStyle(.secondary)
                        Text(author).textSelection(.enabled)
                    }
                }
                if let version = skill.metadata.version {
                    GridRow {
                        Text("Version").foregroundStyle(.secondary)
                        Text(version).textSelection(.enabled)
                    }
                }
                if let license = skill.metadata.license {
                    GridRow {
                        Text("License").foregroundStyle(.secondary)
                        Text(license).textSelection(.enabled)
                    }
                }
            }
            .font(.subheadline)

            SkillFrontmatterView(fields: extraFrontmatterFields, title: nil)
        }
    }

    /// Agent assignment 区域（F06）。
    @ViewBuilder
    private func agentAssignmentSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent 分配")
                .font(.headline)

            AgentToggleView(skill: skill, viewModel: viewModel)
        }
    }

    /// Markdown 正文区域。
    @ViewBuilder
    private func markdownSection(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文档")
                .font(.headline)

            if skill.markdownBody.isEmpty {
                Text("暂无文档")
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                // `MarkdownContentView` 会异步解析并渲染 Markdown：
                // - `Document(parsing:)` 通过 `.task(id:)` 在后台执行
                // - `LazyVStack` 会延迟渲染屏幕外节点
                // - 解析期间显示轻量的 “Rendering...” 占位文案
                // 这样可以避免大段 Markdown 在主线程触发明显卡顿。
                MarkdownContentView(
                    markdownText: skill.markdownBody,
                    translationScope: displayMode.translationScope,
                    manuallyShowsChineseTranslation: viewModel.isShowingManualTranslation
                )
            }
        }
    }

    /// 手动关联 repository 的区域：仅在 skill 没有 `lockEntry` 时展示。
    ///
    /// 用户可以输入 GitHub repository 地址（`owner/repo` 或完整 URL）。
    /// 关联完成后，SkillsMaster 就能为该 skill 执行更新检查。关联信息只写入私有 cache，不会修改 `lock file`。
    @ViewBuilder
    private func linkToRepoSection(_ skill: Skill) -> some View {
        // 先把 `@Observable` 属性读到本地变量里，避免在深层 `ViewBuilder` 中多次访问时
        // 触发 `AttributeGraph` 的依赖环。
        // 本地变量只会建立一次依赖追踪，可以降低循环依赖出现的概率。
        let isLinking = viewModel.isLinking
        let linkError = viewModel.linkError
        let inputIsEmpty = viewModel.repoURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 8) {
            Text("包信息")
                .font(.headline)

            pathRow(skill)

            Text("当前 Skill 尚未关联 Repository。完成关联后才能检查更新。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 输入区：`TextField` + `关联` 按钮。
            HStack(spacing: 8) {
                // `$viewModel.repoURLInput` 是输入内容的双向绑定。
                // `@Bindable` 让 `@Observable` 对象的属性也能支持 `$` 语法。
                TextField("owner/repo", text: $viewModel.repoURLInput)
                    .textFieldStyle(.roundedBorder)
                    // `.onSubmit` 会在用户按下回车时触发。
                    .onSubmit {
                        Task { await viewModel.linkToRepository(skill: skill) }
                    }
                    .disabled(isLinking)

                if isLinking {
                    // 关联ing 中：显示 `ProgressView` 作为 loading 指示器。
                    ProgressView()
                        .controlSize(.small)
                    Text("关联ing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("关联") {
                        Task { await viewModel.linkToRepository(skill: skill) }
                    }
                    .disabled(inputIsEmpty)
                }
            }

            // 错误信息。
            if let error = linkError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// lock file 信息区域。
    @ViewBuilder
    private func lockFileSection(_ skill: Skill, _ lockEntry: LockEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行：`包信息` + 更新检查按钮。
            HStack {
                Text("包信息")
                    .font(.headline)

                Spacer()

                // F12: 更新状态指示和操作按钮
                if canCheckUpdate(skill) {
                    updateStatusView(skill)
                }
            }

            // `Grid` 是 macOS 14+ 提供的网格布局，概念上类似 HTML 的 CSS Grid。
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Path").foregroundStyle(.secondary)
                    pathValueView(skill)
                }
                GridRow {
                    Text("Source").foregroundStyle(.secondary)
                    Text(lockEntry.source).textSelection(.enabled)
                }
                GridRow {
                    Text(sourceLocationLabel(for: lockEntry)).foregroundStyle(.secondary)
                    // 如果 `sourceUrl` 是合法 URL，就展示为可点击链接，并在点击后交给系统默认浏览器打开。
                    if let url = URL(string: lockEntry.sourceUrl),
                       url.scheme != nil {
                        Link(lockEntry.sourceUrl, destination: url)
                            .textSelection(.enabled)
                    } else {
                        Text(lockEntry.sourceUrl).textSelection(.enabled)
                    }
                }
                if let sourceVersion = lockEntry.sourceVersion, !sourceVersion.isEmpty {
                    GridRow {
                        Text("Version").foregroundStyle(.secondary)
                        Text(sourceVersion).textSelection(.enabled)
                    }
                }
                if let originType = lockEntry.originSourceType, !originType.isEmpty {
                    GridRow {
                        Text("Upstream").foregroundStyle(.secondary)
                        upstreamValueView(lockEntry)
                    }
                }
                // 优先展示 commit hash（可直接映射到 GitHub commit 页面），
                // 如果没有 commit hash，再回退到 tree hash（通常表示旧 skill 尚未完成 backfill）。
                if canCheckGitUpdate(skill) {
                    GridRow {
                        if let commitHash = skill.localCommitHash {
                            Text("Commit").foregroundStyle(.secondary)
                            Text(commitHash)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            Text("Tree Hash").foregroundStyle(.secondary)
                            Text(lockEntry.skillFolderHash)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                GridRow {
                    Text("Installed").foregroundStyle(.secondary)
                    Text(lockEntry.installedAt.formattedDate)
                }
                GridRow {
                    Text("Updated").foregroundStyle(.secondary)
                    Text(lockEntry.updatedAt.formattedDate)
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func pathRow(_ skill: Skill) -> some View {
        HStack(spacing: 6) {
            Text(skill.canonicalURL.tildeAbbreviatedPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            copyPathButton(skill)
        }
    }

    @ViewBuilder
    private func pathValueView(_ skill: Skill) -> some View {
        HStack(spacing: 6) {
            Text(skill.canonicalURL.tildeAbbreviatedPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            copyPathButton(skill)
        }
    }

    private func copyPathButton(_ skill: Skill) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(skill.canonicalURL.path, forType: .string)

            pathCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                pathCopied = false
            }
        } label: {
            Image(systemName: pathCopied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(pathCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help("复制路径到剪贴板")
        .animation(.easeInOut(duration: 0.2), value: pathCopied)
    }

    /// F12：更新状态指示区域。
    ///
    /// 会根据 `viewModel` 当前的更新状态展示不同 UI：
    /// - `Checking`：`ProgressView` + `检查中...`
    /// - `Has update`：橙色提示 + `更新` 按钮
    /// - `Updating`：`ProgressView` + `更新中...`
    /// - `Up to date`：绿色勾选（2 秒后自动消失）
    /// - 默认状态：展示检查按钮
    @ViewBuilder
    private func updateStatusView(_ skill: Skill) -> some View {
        if viewModel.isCheckingUpdate {
            // 正在检查更新。
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("检查中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.isUpdating {
            // 正在执行更新。
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("更新中...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if skill.hasUpdate {
            // 检测到可用更新：展示 hash 对比、GitHub 链接和 `更新` 按钮。
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Label("发现更新", systemImage: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Button("更新") {
                        Task { await viewModel.updateSkill(skill) }
                    }
                    .controlSize(.small)
                }

                // commit hash 对比行 + GitHub 链接。
                // 这里展示 `localHash → remoteHash` 的 7 位短哈希格式，与 `git log --oneline` 保持一致。
                updateDetailRow(skill)
            }
        } else if viewModel.showUpToDate {
            // 已是最新版本（2 秒后自动消失）。
            Label("已是最新", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let error = viewModel.updateError {
            // 更新检查出错
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            // 默认状态：展示检查按钮。
            Button {
                Task { await viewModel.checkForUpdate(skill: skill) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .help("Check for updates")
        }
    }

    /// F12：更新详情行，用于展示 commit hash 对比和 GitHub 链接。
    ///
    /// 布局大致为：`abc1234 → def5678   在 GitHub 查看变更 ↗`
    /// - hash 对比：`local commit hash → remote commit hash`
    /// - GitHub 链接：点击后在浏览器中打开 compare 页面
    @ViewBuilder
    private func updateDetailRow(_ skill: Skill) -> some View {
        HStack(spacing: 6) {
            if skill.lockEntry?.sourceType == "skillhub" {
                let currentVersion = skill.lockEntry?.sourceVersion ?? "unknown"
                if let remoteVersion = skill.remoteVersion {
                    Text("\(currentVersion) → \(remoteVersion)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                // 取前 7 位作为短哈希格式，与 `git log --oneline` 保持一致。
                // `prefix(_:)` 返回的是 `Substring`，因此这里需要再包一层 `String()`。
                let localShort = skill.localCommitHash.map { String($0.prefix(7)) }
                let remoteShort = skill.remoteCommitHash.map { String($0.prefix(7)) }

                if let localShort, let remoteShort {
                    // 本地和远端 commit hash 都存在时，展示 `abc1234 → def5678` 对比。
                    Text("\(localShort) → \(remoteShort)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if let remoteShort {
                    // 只有远端 commit hash 时，走降级展示（通常表示旧 skill 的 backfill 没成功）。
                    Text("→ \(remoteShort)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // GitHub compare 链接按钮。
                if let url = githubCompareURL(skill) {
                    // 使用 link 风格按钮，点击后在浏览器中打开。
                    // `NSWorkspace.shared.open()` 是 macOS 中打开 URL 的标准方式。
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 2) {
                            Text("在 GitHub 查看变更")
                            // `arrow.up.right` 是常见的 external link 图标（↗）。
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// 生成 GitHub compare URL。
    ///
    /// 这里会基于 `lockEntry.sourceUrl` 和 commit hash 生成对应页面：
    /// - 如果本地与远端 hash 都存在：生成 `compare/<local>...<remote>` 链接
    /// - 如果只有远端 hash：生成 `commit/<remote>` 链接
    private func githubCompareURL(_ skill: Skill) -> URL? {
        guard let sourceUrl = skill.lockEntry?.sourceUrl,
              let baseURL = GitService.githubWebURL(from: sourceUrl),
              let remoteHash = skill.remoteCommitHash else {
            return nil
        }

        // 如果存在本地 commit hash，就生成 compare URL 来查看两次提交之间的差异。
        // GitHub compare URL 的格式是 `compare/<base>...<head>`。
        if let localHash = skill.localCommitHash {
            return URL(string: "\(baseURL)/compare/\(localHash)...\(remoteHash)")
        }

        // 如果没有本地 commit hash（通常表示 backfill 未成功），就退化为只打开远端 commit 页面。
        return URL(string: "\(baseURL)/commit/\(remoteHash)")
    }

    /// 仅 Git 来源支持更新检查（custom repository 也属于 Git 语义）。
    private func canCheckUpdate(_ skill: Skill) -> Bool {
        guard let sourceType = skill.lockEntry?.sourceType else { return false }
        return sourceType != "local" && sourceType != "clawhub"
    }

    private func sourceLocationLabel(for lockEntry: LockEntry) -> String {
        switch lockEntry.sourceType {
        case "clawhub", "skillhub":
            return "Marketplace"
        default:
            return "Repository"
        }
    }

    @ViewBuilder
    private func upstreamValueView(_ lockEntry: LockEntry) -> some View {
        let label = {
            switch lockEntry.originSourceType {
            case "clawhub":
                return "ClawHub"
            default:
                return lockEntry.originSourceType ?? "Unknown"
            }
        }()

        if let urlString = lockEntry.originSourceUrl,
           let url = URL(string: urlString),
           url.scheme != nil {
            HStack(spacing: 6) {
                Text(label)
                Text(lockEntry.originSource ?? urlString)
                    .foregroundStyle(.secondary)
                Link("打开", destination: url)
            }
            .textSelection(.enabled)
        } else {
            Text(lockEntry.originSource ?? label).textSelection(.enabled)
        }
    }

    private func canCheckGitUpdate(_ skill: Skill) -> Bool {
        guard let sourceType = skill.lockEntry?.sourceType else { return false }
        return sourceType != "local" && sourceType != "clawhub" && sourceType != "skillhub"
    }
}
