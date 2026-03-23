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
            "未保存修改",
            isPresented: Binding(
                get: { viewModel.pendingNavigationAction != nil },
                set: { if !$0 { viewModel.cancelPendingNavigationAction() } }
            ),
            titleVisibility: .visible
        ) {
            Button("保存") {
                Task { _ = await viewModel.savePendingNavigationAction() }
            }
            Button("放弃修改", role: .destructive) {
                viewModel.discardPendingNavigationAction()
            }
            Button("取消", role: .cancel) {
                viewModel.cancelPendingNavigationAction()
            }
        } message: {
            Text("当前文件有未保存修改。")
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
                detailRow("根目录", value: viewModel.rootDisplayPath)
                detailRow("状态", value: viewModel.rootExists ? "已存在" : "尚未创建")
                detailRow("受保护路径", value: viewModel.protectedURL.path)
            }
            .font(.subheadline)

            protectionNotice(
                title: "只读保护",
                message: "`skills/` 目录及其全部子内容由 SkillsMaster 管理。在 Agent Files 中只能浏览与跳转，不能新建、重命名、删除或打开到外部编辑器。"
            )

            if !viewModel.rootExists {
                Text("当前根目录不存在。使用左侧工具栏新建文件或文件夹时，SkillsMaster 会自动创建该 Agent 的配置目录。")
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
                        Text("只读")
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
                detailRow("路径", value: item.url.path)
                detailRow("相对路径", value: item.relativePath)
                detailRow("类型", value: itemTypeDescription(item))
                detailRow("隐藏文件", value: item.isHidden ? "是" : "否")
                detailRow("Symbolic Link", value: item.isSymbolicLink ? "是" : "否")

                if item.isDirectory {
                    if let loadedChildCount = viewModel.loadedChildCount(for: item) {
                        detailRow("已加载子项", value: "\(loadedChildCount)")
                    } else {
                        detailRow("已加载子项", value: "展开目录后加载")
                    }
                } else if viewModel.isLoadingSelectedItemDetails {
                    detailRow("详情", value: "加载中...")
                } else if let details = viewModel.selectedItemDetails {
                    if let modifiedDate = details.modifiedDate {
                        detailRow("修改时间", value: dateFormatter.string(from: modifiedDate))
                    }
                    if let fileSize = details.fileSize {
                        detailRow("大小", value: byteCountFormatter.string(fromByteCount: Int64(fileSize)))
                    }
                    detailRow("文本文件", value: details.isTextFile ? "是" : "否")
                }
            }
            .font(.subheadline)

            if let reason = item.protectionReason {
                protectionNotice(title: "受保护路径", message: reason)
            } else if item.isSymbolicLink {
                Text("当前项是 symbolic link。列表中只展示链接本身，不会递归展开其目标目录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let details = viewModel.selectedItemDetails,
                      !item.isDirectory,
                      !details.isTextFile {
                Text("当前只允许通过系统默认应用打开文本文件。非文本文件可在 Finder 中定位后自行处理。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !item.isDirectory,
                      !item.isSymbolicLink,
                      viewModel.previewViewModel == nil,
                      viewModel.selectedItemDetails?.isTextFile == true {
                Text("当前文本文件暂不支持内置预览，可通过外置编辑器查看。")
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
            Text("内容")
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
            Text("操作")
                .font(.headline)

            HStack(spacing: 12) {
                if canEditInternally {
                    Button("编辑") {
                        viewModel.startEditingSelectedItem()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if canOpenInExternalEditor {
                    Button("外置编辑器打开") {
                        viewModel.openSelectedInExternalEditor()
                    }
                    .buttonStyle(.bordered)
                }

                Button("在 Finder 中显示") {
                    viewModel.revealSelectedOrRootInFinder()
                }
                .buttonStyle(.bordered)
                .disabled(!canRevealInFinder)

                Button("在 Terminal 中打开") {
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
            .help("在 Finder 中显示")
            .disabled(!viewModel.canRevealSelectedOrRoot)

            Button {
                viewModel.openSelectedOrRootInTerminal()
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help("在 Terminal 中打开")
            .disabled(!viewModel.canOpenSelectedOrRootInTerminal)

            if viewModel.canEditSelectedInternally {
                Button {
                    viewModel.startEditingSelectedItem()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑")
            }

            if viewModel.canOpenSelectedInExternalEditor {
                Button {
                    viewModel.openSelectedInExternalEditor()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("在外置编辑器中打开")
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
            return item.isSymbolicLink ? "文件夹 symbolic link" : "文件夹"
        }
        if item.isSymbolicLink {
            return "文件 symbolic link"
        }
        return "文件"
    }
}
