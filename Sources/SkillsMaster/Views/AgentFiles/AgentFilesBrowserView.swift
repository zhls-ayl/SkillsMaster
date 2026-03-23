import SwiftUI

struct AgentFilesBrowserView: View {

    @Bindable var viewModel: AgentFilesViewModel

    @State private var namePrompt: NamePromptContext?
    @State private var pendingDeleteItem: AgentFileItem?
    @State private var pendingOverwriteAction: PendingOverwriteAction?
    @State private var localErrorMessage: String?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView("Loading files...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty {
                EmptyStateView(
                    icon: viewModel.rootExists ? "folder" : "folder.badge.questionmark",
                    title: viewModel.rootExists ? "目录为空" : "根目录尚未创建",
                    subtitle: viewModel.rootExists
                        ? "使用工具栏新建文件或文件夹。"
                        : "使用工具栏新建文件或文件夹时，SkillsMaster 会自动创建该 Agent 的根目录。"
                )
            } else {
                List(selection: $viewModel.selectedItemID) {
                    AgentFileTreeRowsView(
                        entries: viewModel.entries,
                        depth: 0,
                        viewModel: viewModel
                    )
                }
            }
        }
        .navigationTitle(viewModel.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    namePrompt = .newFile
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("新建文件")
                .disabled(!viewModel.canCreateInCurrentDirectory)

                Button {
                    namePrompt = .newFolder
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("新建文件夹")
                .disabled(!viewModel.canCreateInCurrentDirectory)

                Button {
                    guard let selectedItem = viewModel.selectedItem else { return }
                    namePrompt = .rename(currentName: selectedItem.name)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("重命名")
                .disabled(!viewModel.canRenameSelectedItem)

                Button(role: .destructive) {
                    pendingDeleteItem = viewModel.selectedItem
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除")
                .disabled(!viewModel.canDeleteSelectedItem)

                Button {
                    viewModel.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
            }
        }
        .task(id: viewModel.agentType) {
            viewModel.reloadIfNeeded()
        }
        .sheet(item: $namePrompt) { prompt in
            NamePromptSheet(
                title: prompt.title,
                actionTitle: prompt.actionTitle,
                initialName: prompt.initialName,
                directoryPath: viewModel.currentCreationDirectoryURL.path,
                onCancel: { namePrompt = nil },
                onConfirm: { name in
                    namePrompt = nil
                    handleNamePrompt(prompt, name: name)
                }
            )
        }
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                do {
                    try viewModel.deleteSelectedItem()
                } catch {
                    localErrorMessage = error.localizedDescription
                }
                pendingDeleteItem = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteItem = nil
            }
        } message: {
            if let pendingDeleteItem {
                Text(deleteMessage(for: pendingDeleteItem))
            }
        }
        .confirmationDialog(
            "目标已存在",
            isPresented: Binding(
                get: { pendingOverwriteAction != nil },
                set: { if !$0 { pendingOverwriteAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("覆盖", role: .destructive) {
                guard let pendingOverwriteAction else { return }
                performOverwrite(pendingOverwriteAction)
                self.pendingOverwriteAction = nil
            }
            Button("取消", role: .cancel) {
                pendingOverwriteAction = nil
            }
        } message: {
            if let pendingOverwriteAction {
                Text(pendingOverwriteAction.message)
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { localErrorMessage != nil || viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        localErrorMessage = nil
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("确定", role: .cancel) {
                localErrorMessage = nil
                viewModel.errorMessage = nil
            }
        } message: {
            Text(localErrorMessage ?? viewModel.errorMessage ?? "未知错误")
        }
    }

    private func handleNamePrompt(_ prompt: NamePromptContext, name: String) {
        do {
            switch prompt.kind {
            case .newFile:
                try viewModel.createFile(named: name)
            case .newFolder:
                try viewModel.createFolder(named: name)
            case .rename:
                try viewModel.renameSelectedItem(to: name)
            }
        } catch let error as AgentFileBrowserService.BrowserError {
            handleBrowserError(error, prompt: prompt, name: name)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func handleBrowserError(
        _ error: AgentFileBrowserService.BrowserError,
        prompt: NamePromptContext,
        name: String
    ) {
        switch error {
        case .itemAlreadyExists:
            pendingOverwriteAction = PendingOverwriteAction(kind: prompt.kind, name: name)
        default:
            localErrorMessage = error.localizedDescription
        }
    }

    private func performOverwrite(_ action: PendingOverwriteAction) {
        do {
            switch action.kind {
            case .newFile:
                try viewModel.createFile(named: action.name, replaceExisting: true)
            case .newFolder:
                try viewModel.createFolder(named: action.name, replaceExisting: true)
            case .rename:
                try viewModel.renameSelectedItem(to: action.name, replaceExisting: true)
            }
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func deleteMessage(for item: AgentFileItem) -> String {
        if item.isDirectory {
            return "这会删除文件夹 “\(item.name)” 及其全部内容，且无法撤销。"
        }
        return "这会删除文件 “\(item.name)”，且无法撤销。"
    }
}

private struct AgentFileTreeRowsView: View {
    let entries: [AgentFileItem]
    let depth: Int
    @Bindable var viewModel: AgentFilesViewModel

    var body: some View {
        ForEach(entries) { item in
            AgentFileRowView(item: item, depth: depth, viewModel: viewModel)
                .tag(item.id)

            if item.isExpandable && viewModel.isExpanded(item) {
                if viewModel.isLoadingChildren(for: item) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, CGFloat(depth + 1) * 18 + 18)
                } else {
                    AgentFileTreeRowsView(
                        entries: viewModel.children(for: item),
                        depth: depth + 1,
                        viewModel: viewModel
                    )
                }
            }
        }
    }
}

private struct AgentFileRowView: View {
    let item: AgentFileItem
    let depth: Int
    @Bindable var viewModel: AgentFilesViewModel

    var body: some View {
        HStack(spacing: 8) {
            disclosureControl

            Image(systemName: item.iconName)
                .foregroundStyle(item.isProtected ? .orange : .secondary)

            Text(item.name)
                .foregroundStyle(item.isHidden ? .secondary : .primary)

            if item.isProtected {
                Spacer(minLength: 8)
                Text("只读")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if item.isSymbolicLink {
                Spacer(minLength: 8)
                Text("symlink")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(depth) * 18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var disclosureControl: some View {
        if item.isExpandable {
            Button {
                viewModel.toggleExpansion(for: item)
            } label: {
                Image(systemName: viewModel.isExpanded(item) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(width: 14, height: 14)
        }
    }
}

private struct NamePromptContext: Identifiable {
    enum Kind {
        case newFile
        case newFolder
        case rename
    }

    let id = UUID()
    let kind: Kind
    let initialName: String

    static let newFile = NamePromptContext(kind: .newFile, initialName: "")
    static let newFolder = NamePromptContext(kind: .newFolder, initialName: "")

    static func rename(currentName: String) -> NamePromptContext {
        NamePromptContext(kind: .rename, initialName: currentName)
    }

    var title: String {
        switch kind {
        case .newFile:
            return "新建文件"
        case .newFolder:
            return "新建文件夹"
        case .rename:
            return "重命名"
        }
    }

    var actionTitle: String {
        switch kind {
        case .rename:
            return "保存"
        case .newFile, .newFolder:
            return "创建"
        }
    }
}

private struct PendingOverwriteAction {
    let kind: NamePromptContext.Kind
    let name: String

    var message: String {
        switch kind {
        case .newFile:
            return "同名文件已存在。确认后会覆盖现有文件。"
        case .newFolder:
            return "同名文件夹或文件已存在。确认后会删除现有目标并创建新的文件夹。"
        case .rename:
            return "目标名称已存在。确认后会删除现有目标并继续重命名。"
        }
    }
}

private struct NamePromptSheet: View {
    let title: String
    let actionTitle: String
    let initialName: String
    let directoryPath: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var name: String

    init(
        title: String,
        actionTitle: String,
        initialName: String,
        directoryPath: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.initialName = initialName
        self.directoryPath = directoryPath
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(directoryPath)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onConfirm(name)
                }

            HStack {
                Spacer()

                Button("取消", role: .cancel) {
                    onCancel()
                }

                Button(actionTitle) {
                    onConfirm(name)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
