import SwiftUI
import AppKit

/// Detail pane for SkillsHub skills, showing archive metadata + rendered SKILL.md content.
struct SkillsHubSkillDetailView: View {
    let skill: SkillsHubSkill
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let viewModel: SkillsHubBrowserViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                packageInfoSection

                if let detail = viewModel.selectedSkillDetail {
                    skillMetadataBlock(
                        detail.content.metadata,
                        frontmatterText: detail.content.frontmatterText
                    )
                }

                Divider()
                actionsSection
                Divider()
                skillContentSection
            }
            .padding()
        }
        .navigationTitle(skill.name)
        .task(id: skill.id) {
            await viewModel.loadSelection(for: skill)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.name)
                    .font(.title)
                    .bold()
                    .textSelection(.enabled)

                if viewModel.isFeatured(skill) {
                    Text("Featured")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }

                if isInstalled {
                    Text("Installed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 4) {
                Text("Slug:")
                    .foregroundStyle(.secondary)
                Text(skill.slug)
                    .textSelection(.enabled)
            }
            .font(.subheadline)

            Text(skill.descriptionText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var packageInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Package Info")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Marketplace").foregroundStyle(.secondary)
                    Text("SkillsHub")
                }
                if let upstream = upstreamDisplayName {
                    GridRow {
                        Text("Upstream").foregroundStyle(.secondary)
                        if let url = upstreamURL {
                            Link(upstream, destination: url)
                        } else {
                            Text(upstream)
                        }
                    }
                }
                if let category = skill.category {
                    GridRow {
                        Text("Category").foregroundStyle(.secondary)
                        Text(category.displayName)
                    }
                }
                GridRow {
                    Text("Downloads").foregroundStyle(.secondary)
                    Text(skill.formattedDownloads)
                }
                GridRow {
                    Text("Installs").foregroundStyle(.secondary)
                    Text(skill.formattedInstalls)
                }
                GridRow {
                    Text("Stars").foregroundStyle(.secondary)
                    Text(skill.formattedStars)
                }
                if let version = viewModel.selectedSkillDetail?.installVersion ?? skill.latestVersion {
                    GridRow {
                        Text("Latest Version").foregroundStyle(.secondary)
                        Text(version).textSelection(.enabled)
                    }
                }
                if let ownerName = skill.ownerName, !ownerName.isEmpty {
                    GridRow {
                        Text("Owner").foregroundStyle(.secondary)
                        Text(ownerName).textSelection(.enabled)
                    }
                }
                if let updatedDate = skill.formattedUpdatedDate {
                    GridRow {
                        Text("Updated").foregroundStyle(.secondary)
                        Text(updatedDate)
                    }
                }
                if let publishedDate = viewModel.selectedSkillDetail?.formattedPublishedDate {
                    GridRow {
                        Text("Published").foregroundStyle(.secondary)
                        Text(publishedDate)
                    }
                }
                if let fileCount = viewModel.selectedSkillDetail?.extractedFiles.count {
                    GridRow {
                        Text("Files").foregroundStyle(.secondary)
                        Text("\(fileCount)")
                    }
                }
            }
            .font(.subheadline)

            if let tags = tagsText {
                HStack(alignment: .top) {
                    Text("Tags")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .frame(width: 72, alignment: .leading)

                    Text(tags)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    onInstall()
                } label: {
                    if isInstalling {
                        Label {
                            Text(viewModel.detailInstallButtonTitle(for: skill))
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Label(
                            viewModel.detailInstallButtonTitle(for: skill),
                            systemImage: viewModel.canReinstall(skill)
                                ? "arrow.triangle.2.circlepath"
                                : "arrow.down.circle"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)

                if let upstreamURL {
                    Button {
                        NSWorkspace.shared.open(upstreamURL)
                    } label: {
                        Label(upstreamButtonTitle, systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Install Targets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(viewModel.targetAgentTypes) { agentType in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedTargetAgents.contains(agentType) },
                            set: { _ in viewModel.toggleTargetAgent(agentType) }
                        )) {
                            HStack(spacing: 6) {
                                AgentIconView(agentType: agentType, size: 13)
                                Text(agentType.displayName)
                            }
                            .font(.caption)
                        }
                        .toggleStyle(.checkbox)
                        .opacity(viewModel.isAgentDetected(agentType) ? 1.0 : 0.5)
                    }
                }

                Text(viewModel.targetSelectionSummary())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("安装时会先写入 SkillsMaster canonical 目录，再按各 Agent 的默认安装方式建立 direct install。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var skillContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skill Content")
                .font(.headline)

            if viewModel.isLoadingDetail {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载 SkillsHub skill 包...")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.detailError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    if let upstreamURL {
                        Button {
                            NSWorkspace.shared.open(upstreamURL)
                        } label: {
                            Label(upstreamButtonTitle, systemImage: "safari")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if let detail = viewModel.selectedSkillDetail {
                MarkdownContentView(markdownText: detail.content.markdownBody)
                    .textSelection(.enabled)
            } else {
                Text("请选择一个 SkillsHub skill 查看详情。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func skillMetadataBlock(_ metadata: SkillMetadata, frontmatterText: String) -> some View {
        let extraFields = FrontmatterDisplay.extraFields(
            from: frontmatterText,
            excluding: ["name", "description", "license"]
        )
        let hasUsefulInfo = metadata.author != nil
            || metadata.version != nil
            || metadata.license != nil
            || !extraFields.isEmpty

        if hasUsefulInfo {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Skill Metadata")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let author = metadata.author {
                        GridRow {
                            Text("Author").foregroundStyle(.secondary)
                            Text(author).textSelection(.enabled)
                        }
                    }
                    if let version = metadata.version {
                        GridRow {
                            Text("Version").foregroundStyle(.secondary)
                            Text(version).textSelection(.enabled)
                        }
                    }
                    if let license = metadata.license {
                        GridRow {
                            Text("License").foregroundStyle(.secondary)
                            Text(license).textSelection(.enabled)
                        }
                    }
                }
                .font(.subheadline)

                SkillFrontmatterView(fields: extraFields, title: nil)
            }
        }
    }

    private var tagsText: String? {
        guard !skill.tags.isEmpty else { return nil }
        return skill.tags.joined(separator: ", ")
    }

    private var upstreamDisplayName: String? {
        switch viewModel.selectedSkillDetail?.originSourceType ?? skill.originSourceType {
        case "clawhub":
            return "ClawHub"
        default:
            return nil
        }
    }

    private var upstreamURL: URL? {
        if let urlString = viewModel.selectedSkillDetail?.originSourceURL ?? skill.originSourceURL {
            return URL(string: urlString)
        }
        return nil
    }

    private var upstreamButtonTitle: String {
        upstreamDisplayName.map { "View on \($0)" } ?? "View Upstream"
    }
}
