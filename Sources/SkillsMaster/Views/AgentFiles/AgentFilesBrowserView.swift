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
                ProgressView(AppLocalization.string("Loading files..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty {
                EmptyStateView(
                    icon: viewModel.rootExists ? "folder" : "folder.badge.questionmark",
                    title: viewModel.rootExists
                        ? AppLocalization.string("Directory is Empty")
                        : AppLocalization.string("Root Directory Not Created"),
                    subtitle: viewModel.rootExists
                        ? AppLocalization.string("Use the toolbar to create a file or folder.")
                        : AppLocalization.string("When you create a file or folder from the toolbar, SkillsMaster creates this Agent's root directory automatically.")
                )
            } else {
                List(selection: selectionBinding) {
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
                .help(AppLocalization.string("New File"))
                .disabled(!viewModel.canCreateInCurrentDirectory || viewModel.isEditingTextFile)

                Button {
                    namePrompt = .newFolder
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help(AppLocalization.string("New Folder"))
                .disabled(!viewModel.canCreateInCurrentDirectory || viewModel.isEditingTextFile)

                Button {
                    guard let selectedItem = viewModel.selectedItem else { return }
                    namePrompt = .rename(currentName: selectedItem.name)
                } label: {
                    Image(systemName: "pencil")
                }
                .help(AppLocalization.string("Rename"))
                .disabled(!viewModel.canRenameSelectedItem || viewModel.isEditingTextFile)

                Button(role: .destructive) {
                    pendingDeleteItem = viewModel.selectedItem
                } label: {
                    Image(systemName: "trash")
                }
                .help(AppLocalization.string("Delete"))
                .disabled(!viewModel.canDeleteSelectedItem || viewModel.isEditingTextFile)

                Button {
                    viewModel.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(AppLocalization.string("Refresh"))
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
            AppLocalization.string("Confirm Deletion"),
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Delete"), role: .destructive) {
                do {
                    try viewModel.deleteSelectedItem()
                } catch {
                    localErrorMessage = error.localizedDescription
                }
                pendingDeleteItem = nil
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {
                pendingDeleteItem = nil
            }
        } message: {
            if let pendingDeleteItem {
                Text(deleteMessage(for: pendingDeleteItem))
            }
        }
        .confirmationDialog(
            AppLocalization.string("Target Already Exists"),
            isPresented: Binding(
                get: { pendingOverwriteAction != nil },
                set: { if !$0 { pendingOverwriteAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Replace"), role: .destructive) {
                guard let pendingOverwriteAction else { return }
                performOverwrite(pendingOverwriteAction)
                self.pendingOverwriteAction = nil
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {
                pendingOverwriteAction = nil
            }
        } message: {
            if let pendingOverwriteAction {
                Text(pendingOverwriteAction.message)
            }
        }
        .alert(
            AppLocalization.string("Action Failed"),
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
            Button(AppLocalization.string("OK"), role: .cancel) {
                localErrorMessage = nil
                viewModel.errorMessage = nil
            }
        } message: {
            Text(localErrorMessage ?? viewModel.errorMessage ?? AppLocalization.string("Unknown Error"))
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedItemID },
            set: { newSelection in
                viewModel.requestSelectionChange(to: newSelection)
            }
        )
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
            return AppLocalization.format(
                "This will permanently delete the folder \"%@\" and all of its contents.",
                item.name
            )
        }
        return AppLocalization.format(
            "This will permanently delete the file \"%@\".",
            item.name
        )
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
                        Text(AppLocalization.string("Loading..."))
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
                Text(AppLocalization.string("Read Only"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if item.isSymbolicLink {
                Spacer(minLength: 8)
                Text(AppLocalization.string("Symbolic Link"))
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
            return AppLocalization.string("New File")
        case .newFolder:
            return AppLocalization.string("New Folder")
        case .rename:
            return AppLocalization.string("Rename")
        }
    }

    var actionTitle: String {
        switch kind {
        case .rename:
            return AppLocalization.string("Save")
        case .newFile, .newFolder:
            return AppLocalization.string("Create")
        }
    }
}

private struct PendingOverwriteAction {
    let kind: NamePromptContext.Kind
    let name: String

    var message: String {
        switch kind {
        case .newFile:
            return AppLocalization.string("A file with the same name already exists. Confirm to replace the existing file.")
        case .newFolder:
            return AppLocalization.string("A file or folder with the same name already exists. Confirm to remove it and create a new folder.")
        case .rename:
            return AppLocalization.string("The target name already exists. Confirm to remove the existing target and continue renaming.")
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
                Text(AppLocalization.string("Directory"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(directoryPath)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            TextField(AppLocalization.string("Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onConfirm(name)
                }

            HStack {
                Spacer()

                Button(AppLocalization.string("Cancel"), role: .cancel) {
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
