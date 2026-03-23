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
        .task(id: viewModel.selectedItemID) {
            viewModel.loadSelectedItemDetails()
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
                canOpenTextFile: false,
                canRevealInFinder: viewModel.canRevealSelectedOrRoot,
                canOpenInTerminal: viewModel.canOpenSelectedOrRootInTerminal
            )
        }
    }

    @ViewBuilder
    private func selectedItemSection(_ item: AgentFileItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    detailRow("详情", value: "Loading...")
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
            } else if let details = viewModel.selectedItemDetails, !item.isDirectory, !details.isTextFile {
                Text("当前只允许通过系统默认应用打开文本文件。非文本文件可在 Finder 中定位后自行处理。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            actionSection(
                canOpenTextFile: viewModel.canOpenSelectedTextFile,
                canRevealInFinder: viewModel.canRevealSelectedOrRoot,
                canOpenInTerminal: viewModel.canOpenSelectedOrRootInTerminal
            )
        }
    }

    @ViewBuilder
    private func actionSection(
        canOpenTextFile: Bool,
        canRevealInFinder: Bool,
        canOpenInTerminal: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("操作")
                .font(.headline)

            HStack(spacing: 12) {
                if canOpenTextFile {
                    Button("系统打开文本文件") {
                        viewModel.openSelectedFileInDefaultApp()
                    }
                    .buttonStyle(.borderedProminent)
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
