import SwiftUI

struct AgentFileDetailView: View {

    @Bindable var viewModel: AgentFilesViewModel

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
                TextFileEditorView(
                    viewModel: editorViewModel,
                    onSave: {
                        _ = await viewModel.saveCurrentEditorAndClose()
                    },
                    onCancel: {
                        viewModel.requestCloseEditor()
                    }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let selectedItem = viewModel.selectedItem {
                            selectedItemSection(selectedItem)
                        } else {
                            rootSection
                        }
                    }
                    .padding()
                }
            }
        }
        .task(id: viewModel.selectedItemID) {
            viewModel.loadSelectedItemDetails()
        }
        .confirmationDialog(
            AppLocalization.string("Unsaved Changes"),
            isPresented: Binding(
                get: { viewModel.pendingNavigationAction != nil },
                set: { if !$0 { viewModel.cancelPendingNavigationAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLocalization.string("Save")) {
                Task { _ = await viewModel.savePendingNavigationAction() }
            }
            Button(AppLocalization.string("Discard Changes"), role: .destructive) {
                viewModel.discardPendingNavigationAction()
            }
            Button(AppLocalization.string("Cancel"), role: .cancel) {
                viewModel.cancelPendingNavigationAction()
            }
        } message: {
            Text(AppLocalization.string("The current file has unsaved changes."))
        }
    }

    @ViewBuilder
    private var rootSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AgentIconView(agentType: viewModel.agentType, size: 18)
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow(AppLocalization.string("Root Directory"), value: viewModel.rootDisplayPath)
                detailRow(
                    AppLocalization.string("Status"),
                    value: viewModel.rootExists
                        ? AppLocalization.string("Exists")
                        : AppLocalization.string("Not Created")
                )
                detailRow(AppLocalization.string("Protected Path"), value: viewModel.protectedURL.path)
            }
            .font(.subheadline)

            protectionNotice(
                title: AppLocalization.string("Read-Only Protection"),
                message: AppLocalization.string("The `skills/` directory and all of its contents are managed by SkillsMaster. In Agent Files you can only browse and navigate them, not create, rename, delete, or open them in an external editor.")
            )

            if !viewModel.rootExists {
                Text(AppLocalization.string("The root directory does not exist yet. When you create a file or folder from the toolbar, SkillsMaster creates this Agent's configuration directory automatically."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            actionSection(
                canEditInternally: false,
                canOpenInExternalEditor: false,
                canRevealInFinder: viewModel.canRevealSelectedOrRoot,
                canOpenInTerminal: viewModel.canOpenSelectedOrRootInTerminal
            )
        }
    }

    @ViewBuilder
    private func selectedItemSection(_ item: AgentFileItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: item.iconName)
                        .foregroundStyle(item.isProtected ? .orange : .secondary)
                        .font(.title3)

                    Text(item.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    if item.isProtected {
                        Text(AppLocalization.string("Read Only"))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if viewModel.previewViewModel != nil {
                    previewActionButtons()
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                detailRow(AppLocalization.string("Path"), value: item.url.path)
                detailRow(AppLocalization.string("Relative Path"), value: item.relativePath)
                detailRow(AppLocalization.string("Type"), value: itemTypeDescription(item))
                detailRow(AppLocalization.string("Hidden"), value: item.isHidden ? AppLocalization.string("Yes") : AppLocalization.string("No"))
                detailRow(AppLocalization.string("Symbolic Link"), value: item.isSymbolicLink ? AppLocalization.string("Yes") : AppLocalization.string("No"))

                if item.isDirectory {
                    if item.isSymbolicLink {
                        detailRow(AppLocalization.string("Loaded Children"), value: AppLocalization.string("Symbolic link targets are not expanded recursively"))
                    } else if let loadedChildCount = viewModel.loadedChildCount(for: item) {
                        detailRow(AppLocalization.string("Loaded Children"), value: "\(loadedChildCount)")
                    } else {
                        detailRow(AppLocalization.string("Loaded Children"), value: AppLocalization.string("Loaded after expanding the directory"))
                    }
                } else if viewModel.isLoadingSelectedItemDetails {
                    detailRow(AppLocalization.string("Details"), value: AppLocalization.string("Loading..."))
                } else if let details = viewModel.selectedItemDetails {
                    if let modifiedDate = details.modifiedDate {
                        detailRow(AppLocalization.string("Modified"), value: dateFormatter.string(from: modifiedDate))
                    }
                    if let fileSize = details.fileSize {
                        detailRow(AppLocalization.string("Size"), value: byteCountFormatter.string(fromByteCount: Int64(fileSize)))
                    }
                    detailRow(AppLocalization.string("Text File"), value: details.isTextFile ? AppLocalization.string("Yes") : AppLocalization.string("No"))
                }
            }
            .font(.subheadline)

            if let reason = item.protectionReason {
                protectionNotice(title: AppLocalization.string("Protected Path"), message: reason)
            } else if item.isSymbolicLink {
                Text(AppLocalization.string("This item is a symbolic link. The list only shows the link itself and does not recursively expand its target directory."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let details = viewModel.selectedItemDetails,
                      !item.isDirectory,
                      !details.isTextFile {
                Text(AppLocalization.string("Only text files can be opened from here with the system default app. For non-text files, locate them in Finder and handle them there."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !item.isDirectory,
                      !item.isSymbolicLink,
                      viewModel.previewViewModel == nil,
                      viewModel.selectedItemDetails?.isTextFile == true {
                Text(AppLocalization.string("This text file does not support the built-in preview yet. Use an external editor to inspect it."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let previewViewModel = viewModel.previewViewModel {
                previewSection(previewViewModel)
            } else {
                actionSection(
                    canEditInternally: viewModel.canEditSelectedInternally,
                    canOpenInExternalEditor: viewModel.canOpenSelectedInExternalEditor,
                    canRevealInFinder: viewModel.canRevealSelectedOrRoot,
                    canOpenInTerminal: viewModel.canOpenSelectedOrRootInTerminal
                )
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ previewViewModel: TextFilePreviewViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("Content"))
                .font(.headline)

            TextFilePreviewView(viewModel: previewViewModel)
        }
    }

    @ViewBuilder
    private func actionSection(
        canEditInternally: Bool,
        canOpenInExternalEditor: Bool,
        canRevealInFinder: Bool,
        canOpenInTerminal: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLocalization.string("Actions"))
                .font(.headline)

            HStack(spacing: 12) {
                if canEditInternally {
                    Button(AppLocalization.string("Edit")) {
                        viewModel.startEditingSelectedItem()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if canOpenInExternalEditor {
                    Button(AppLocalization.string("Open in External Editor")) {
                        viewModel.openSelectedInExternalEditor()
                    }
                    .buttonStyle(.bordered)
                }

                Button(AppLocalization.string("Show in Finder")) {
                    viewModel.revealSelectedOrRootInFinder()
                }
                .buttonStyle(.bordered)
                .disabled(!canRevealInFinder)

                Button(AppLocalization.string("Open in Terminal")) {
                    viewModel.openSelectedOrRootInTerminal()
                }
                .buttonStyle(.bordered)
                .disabled(!canOpenInTerminal)
            }
        }
    }

    @ViewBuilder
    private func previewActionButtons() -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.revealSelectedOrRootInFinder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(AppLocalization.string("Show in Finder"))
            .disabled(!viewModel.canRevealSelectedOrRoot)

            Button {
                viewModel.openSelectedOrRootInTerminal()
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help(AppLocalization.string("Open in Terminal"))
            .disabled(!viewModel.canOpenSelectedOrRootInTerminal)

            if viewModel.canEditSelectedInternally {
                Button {
                    viewModel.startEditingSelectedItem()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(AppLocalization.string("Edit"))
            }

            if viewModel.canOpenSelectedInExternalEditor {
                Button {
                    viewModel.openSelectedInExternalEditor()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help(AppLocalization.string("Open in External Editor"))
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func protectionNotice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.shield")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func itemTypeDescription(_ item: AgentFileItem) -> String {
        if item.isDirectory {
            return item.isSymbolicLink
                ? AppLocalization.string("Folder Symbolic Link")
                : AppLocalization.string("Folder")
        }
        if item.isSymbolicLink {
            return AppLocalization.string("File Symbolic Link")
        }
        return AppLocalization.string("File")
    }
}
