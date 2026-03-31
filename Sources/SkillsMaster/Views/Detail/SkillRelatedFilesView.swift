import SwiftUI

struct SkillRelatedFilesDrawerView: View {

    @Bindable var viewModel: SkillRelatedFilesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if viewModel.isLoading && viewModel.nodes.isEmpty {
                ProgressView(appLocalized("Scanning related files..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.nodes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(appLocalized("Retry")) {
                        viewModel.reload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else if viewModel.filteredNodes.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: appLocalized("No matching files"),
                    subtitle: appLocalized("Try a different search term.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        homeRow

                        SkillFileTreeRowsView(
                            nodes: viewModel.filteredNodes,
                            depth: 0,
                            viewModel: viewModel
                        )
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(appLocalized("Files in this Skill"), systemImage: "doc.on.doc")
                        .font(.headline)

                    Text(viewModel.skillRootURL.tildeAbbreviatedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Text("\(viewModel.extraItemCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
            }

            if viewModel.shouldShowSearch {
                TextField(appLocalized("Search files..."), text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
    }

    private var homeRow: some View {
        Button {
            viewModel.requestHomeSelection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "house")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SKILL.md")
                        .foregroundStyle(.primary)

                    Text(appLocalized("Home"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground(isSelected: viewModel.isShowingHomeContent))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
    }
}

private struct SkillFileTreeRowsView: View {
    let nodes: [SkillRelatedFileNode]
    let depth: Int
    @Bindable var viewModel: SkillRelatedFilesViewModel

    var body: some View {
        ForEach(nodes) { node in
            SkillFileTreeRowView(node: node, depth: depth, viewModel: viewModel)

            if node.item.isExpandable && viewModel.isExpanded(node) && !node.children.isEmpty {
                SkillFileTreeRowsView(
                    nodes: node.children,
                    depth: depth + 1,
                    viewModel: viewModel
                )
            }
        }
    }
}

private struct SkillFileTreeRowView: View {
    let node: SkillRelatedFileNode
    let depth: Int
    @Bindable var viewModel: SkillRelatedFilesViewModel

    var body: some View {
        Button {
            if node.item.isDirectory {
                viewModel.toggleExpansion(for: node)
            } else {
                viewModel.requestSelectionChange(to: node.id)
            }
        } label: {
            HStack(spacing: 8) {
                disclosureControl

                Image(systemName: iconName)
                    .foregroundStyle(.secondary)

                Text(node.item.name)
                    .foregroundStyle(node.item.isHidden ? .secondary : .primary)

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectionBackground)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        if node.item.isSymbolicLink {
            return node.item.isDirectory ? "folder.badge.questionmark" : "link"
        }
        return node.item.isDirectory ? "folder" : "doc"
    }

    @ViewBuilder
    private var disclosureControl: some View {
        if node.item.isExpandable {
            Image(systemName: viewModel.isExpanded(node) ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)
        } else {
            Color.clear
                .frame(width: 12, height: 12)
        }
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(viewModel.selectedItemID == node.id ? Color.accentColor.opacity(0.14) : .clear)
    }
}

struct SkillRelatedFileContentView: View {

    @Bindable var viewModel: SkillRelatedFilesViewModel

    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if let editorViewModel = viewModel.editorViewModel {
                VStack(spacing: 0) {
                    contextBar

                    Divider()

                    TextFileEditorView(
                        viewModel: editorViewModel,
                        onSave: {
                            _ = await viewModel.saveCurrentEditorAndClose()
                        },
                        onCancel: {
                            viewModel.requestCloseEditor()
                        }
                    )
                }
            } else if let missingSelectionPath = viewModel.missingSelectionPath {
                VStack(spacing: 0) {
                    contextBar

                    Divider()

                    missingState(path: missingSelectionPath)
                }
            } else if let selectedItem = viewModel.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        contextBar

                        if let externalChangeMessage = viewModel.externalChangeMessage {
                            Label(externalChangeMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        fileHeader(for: selectedItem)

                        metadataSection(for: selectedItem)

                        if let previewViewModel = viewModel.previewViewModel {
                            previewSection(previewViewModel)
                        } else if viewModel.isLoadingSelectedItemDetails {
                            ProgressView(appLocalized("Loading preview..."))
                        } else {
                            unsupportedSection(for: selectedItem)
                        }
                    }
                    .padding()
                }
            } else {
                EmptyView()
            }
        }
        .confirmationDialog(
            appLocalized("Unsaved Changes"),
            isPresented: Binding(
                get: { viewModel.pendingNavigationAction != nil },
                set: { if !$0 { viewModel.cancelPendingNavigationAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button(appLocalized("Save")) {
                Task { _ = await viewModel.savePendingNavigationAction() }
            }
            Button(appLocalized("Discard Changes"), role: .destructive) {
                viewModel.discardPendingNavigationAction()
            }
            Button(appLocalized("Cancel"), role: .cancel) {
                viewModel.cancelPendingNavigationAction()
            }
        } message: {
            Text(appLocalized("The current file has unsaved changes."))
        }
    }

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                viewModel.requestHomeSelection()
            } label: {
                Label(appLocalized("Back to SKILL.md"), systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)

            Text(viewModel.currentRelativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func fileHeader(for item: AgentFileItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(item.url.tildeAbbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    viewModel.revealSelectedOrRootInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help(appLocalized("Show in Finder"))

                Button {
                    viewModel.openSelectedOrRootInTerminal()
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .help(appLocalized("Open in Terminal"))

                if viewModel.canEditSelectedFile {
                    Button {
                        viewModel.startEditingSelectedFile()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help(appLocalized("Edit"))
                }

                if viewModel.canOpenSelectedInExternalEditor {
                    Button {
                        viewModel.openSelectedInExternalEditor()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help(appLocalized("Open in External Editor"))
                }
            }
        }
    }

    private func metadataSection(for item: AgentFileItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalized("File Info"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow(appLocalized("Relative Path"), value: item.relativePath)
                detailRow(appLocalized("Type"), value: itemTypeDescription(item))
                detailRow(appLocalized("Hidden"), value: item.isHidden ? appLocalized("Yes") : appLocalized("No"))
                detailRow(appLocalized("Symbolic Link"), value: item.isSymbolicLink ? appLocalized("Yes") : appLocalized("No"))

                if viewModel.isLoadingSelectedItemDetails {
                    detailRow(appLocalized("Details"), value: appLocalized("Loading..."))
                } else if let details = viewModel.selectedItemDetails {
                    if let modifiedDate = details.modifiedDate {
                        detailRow(appLocalized("Modified"), value: dateFormatter.string(from: modifiedDate))
                    }
                    if let fileSize = details.fileSize {
                        detailRow(
                            appLocalized("Size"),
                            value: byteCountFormatter.string(fromByteCount: Int64(fileSize))
                        )
                    }
                    detailRow(appLocalized("Text File"), value: details.isTextFile ? appLocalized("Yes") : appLocalized("No"))
                }
            }
            .font(.subheadline)
        }
    }

    private func previewSection(_ previewViewModel: TextFilePreviewViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Content"))
                .font(.headline)

            TextFilePreviewView(viewModel: previewViewModel)
        }
    }

    @ViewBuilder
    private func unsupportedSection(for item: AgentFileItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLocalized("Preview unavailable"))
                .font(.headline)

            Text(unsupportedDescription(for: item))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(appLocalized("Show in Finder")) {
                    viewModel.revealSelectedOrRootInFinder()
                }
                .buttonStyle(.bordered)

                if viewModel.canOpenSelectedInExternalEditor {
                    Button(appLocalized("Open in External Editor")) {
                        viewModel.openSelectedInExternalEditor()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func missingState(path: String) -> some View {
        VStack(spacing: 20) {
            EmptyStateView(
                icon: "questionmark.folder",
                title: appLocalized("File not found"),
                subtitle: appLocalized("The selected file no longer exists in this Skill.")
            )

            Text(URL(fileURLWithPath: path).tildeAbbreviatedPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Button(appLocalized("Back to SKILL.md")) {
                viewModel.requestHomeSelection()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func itemTypeDescription(_ item: AgentFileItem) -> String {
        if item.isSymbolicLink {
            return item.isDirectory ? appLocalized("Folder Symbolic Link") : appLocalized("File Symbolic Link")
        }
        return item.isDirectory ? appLocalized("Folder") : appLocalized("File")
    }

    private func unsupportedDescription(for item: AgentFileItem) -> String {
        if viewModel.selectedItemDetails?.isTextFile == true {
            return appLocalized("This text file does not support the built-in preview yet. Use an external editor to inspect it.")
        }
        if item.isSymbolicLink {
            return appLocalized("Symbolic links are shown for inspection only. Open the linked item in Finder or an external editor to inspect it.")
        }
        return appLocalized("This file can't be previewed in SkillsMaster yet. Use Finder or an external editor to inspect it.")
    }
}
