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
            "Unsaved Changes",
            isPresented: Binding(
                get: { viewModel.pendingNavigationAction != nil },
                set: { if !$0 { viewModel.cancelPendingNavigationAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { _ = await viewModel.savePendingNavigationAction() }
            }
            Button("Discard Changes", role: .destructive) {
                viewModel.discardPendingNavigationAction()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingNavigationAction()
            }
        } message: {
            Text("The current file has unsaved changes.")
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
                detailRow("Root Directory", value: viewModel.rootDisplayPath)
                detailRow("Status", value: viewModel.rootExists ? "Exists" : "Not Created")
                detailRow("Protected Path", value: viewModel.protectedURL.path)
            }
            .font(.subheadline)

            protectionNotice(
                title: "Read-Only Protection",
                message: "The `skills/` directory and all of its contents are managed by SkillsMaster. In Agent Files you can only browse and navigate them, not create, rename, delete, or open them in an external editor."
            )

            if !viewModel.rootExists {
                Text("The root directory does not exist yet. When you create a file or folder from the toolbar, SkillsMaster creates this Agent's configuration directory automatically.")
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
                        Text("Read Only")
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
                detailRow("Path", value: item.url.path)
                detailRow("Relative Path", value: item.relativePath)
                detailRow("Type", value: itemTypeDescription(item))
                detailRow("Hidden", value: item.isHidden ? "Yes" : "No")
                detailRow("Symbolic Link", value: item.isSymbolicLink ? "Yes" : "No")

                if item.isDirectory {
                    if item.isSymbolicLink {
                        detailRow("Loaded Children", value: "Symbolic link targets are not expanded recursively")
                    } else if let loadedChildCount = viewModel.loadedChildCount(for: item) {
                        detailRow("Loaded Children", value: "\(loadedChildCount)")
                    } else {
                        detailRow("Loaded Children", value: "Loaded after expanding the directory")
                    }
                } else if viewModel.isLoadingSelectedItemDetails {
                    detailRow("Details", value: "Loading...")
                } else if let details = viewModel.selectedItemDetails {
                    if let modifiedDate = details.modifiedDate {
                        detailRow("Modified", value: dateFormatter.string(from: modifiedDate))
                    }
                    if let fileSize = details.fileSize {
                        detailRow("Size", value: byteCountFormatter.string(fromByteCount: Int64(fileSize)))
                    }
                    detailRow("Text File", value: details.isTextFile ? "Yes" : "No")
                }
            }
            .font(.subheadline)

            if let reason = item.protectionReason {
                protectionNotice(title: "Protected Path", message: reason)
            } else if item.isSymbolicLink {
                Text("This item is a symbolic link. The list only shows the link itself and does not recursively expand its target directory.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let details = viewModel.selectedItemDetails,
                      !item.isDirectory,
                      !details.isTextFile {
                Text("Only text files can be opened from here with the system default app. For non-text files, locate them in Finder and handle them there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !item.isDirectory,
                      !item.isSymbolicLink,
                      viewModel.previewViewModel == nil,
                      viewModel.selectedItemDetails?.isTextFile == true {
                Text("This text file does not support the built-in preview yet. Use an external editor to inspect it.")
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
            Text("Content")
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
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                if canEditInternally {
                    Button("Edit") {
                        viewModel.startEditingSelectedItem()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if canOpenInExternalEditor {
                    Button("Open in External Editor") {
                        viewModel.openSelectedInExternalEditor()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Show in Finder") {
                    viewModel.revealSelectedOrRootInFinder()
                }
                .buttonStyle(.bordered)
                .disabled(!canRevealInFinder)

                Button("Open in Terminal") {
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
            .help("Show in Finder")
            .disabled(!viewModel.canRevealSelectedOrRoot)

            Button {
                viewModel.openSelectedOrRootInTerminal()
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help("Open in Terminal")
            .disabled(!viewModel.canOpenSelectedOrRootInTerminal)

            if viewModel.canEditSelectedInternally {
                Button {
                    viewModel.startEditingSelectedItem()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit")
            }

            if viewModel.canOpenSelectedInExternalEditor {
                Button {
                    viewModel.openSelectedInExternalEditor()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Open in External Editor")
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
            return item.isSymbolicLink ? "Folder Symbolic Link" : "Folder"
        }
        if item.isSymbolicLink {
            return "File Symbolic Link"
        }
        return "File"
    }
}
