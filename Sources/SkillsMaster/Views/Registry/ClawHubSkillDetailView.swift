import SwiftUI
import AppKit

/// Detail pane for ClawHub skills, showing metadata + rendered SKILL.md content.
struct ClawHubSkillDetailView: View {
    let skill: ClawHubSkill
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    let viewModel: ClawHubBrowserViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                packageInfoSection

                if let content = viewModel.fetchedContent {
                    skillMetadataSection(content.metadata, frontmatterText: content.frontmatterText)
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
        .toolbar {
            ToolbarItemGroup {
                ManualTranslationToolbarButton(
                    isActive: viewModel.isShowingManualTranslation(for: skill.id)
                ) {
                    viewModel.toggleManualTranslation(for: skill.id)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.name)
                    .font(.title)
                    .bold()
                    .textSelection(.enabled)

                if isInstalled {
                    Text(appLocalized("Installed"))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 4) {
                Text(appLocalized("Slug:"))
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
            Text(appLocalized("Package Info"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(appLocalized("Marketplace")).foregroundStyle(.secondary)
                    Text(appLocalized("ClawHub"))
                }
                GridRow {
                    Text(appLocalized("Downloads")).foregroundStyle(.secondary)
                    Text(skill.formattedDownloads)
                }
                GridRow {
                    Text(appLocalized("Stars")).foregroundStyle(.secondary)
                    Text(skill.formattedStars)
                }
                if let version = viewModel.selectedSkillDetail?.installVersion ?? skill.latestVersion {
                    GridRow {
                        Text(appLocalized("Latest Version")).foregroundStyle(.secondary)
                        Text(version).textSelection(.enabled)
                    }
                }
                if let owner = ownerText {
                    GridRow {
                        Text(appLocalized("Owner")).foregroundStyle(.secondary)
                        Text(owner).textSelection(.enabled)
                    }
                }
                if let updatedDate = skill.formattedUpdatedDate {
                    GridRow {
                        Text(appLocalized("Updated")).foregroundStyle(.secondary)
                        Text(updatedDate)
                    }
                }
                if let publishedDate = viewModel.selectedSkillDetail?.formattedLatestVersionDate {
                    GridRow {
                        Text(appLocalized("Latest Publish Date")).foregroundStyle(.secondary)
                        Text(publishedDate)
                    }
                }
                if let license = viewModel.selectedSkillDetail?.license {
                    GridRow {
                        Text(appLocalized("License")).foregroundStyle(.secondary)
                        Text(license)
                    }
                }
                if let moderation = moderationText {
                    GridRow {
                        Text(appLocalized("Moderation")).foregroundStyle(.secondary)
                        Text(moderation)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.subheadline)

            if let detailError = viewModel.detailError {
                Label(detailError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func skillMetadataSection(_ metadata: SkillMetadata, frontmatterText: String) -> some View {
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
                Text(appLocalized("Skill Metadata"))
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let author = metadata.author {
                        GridRow {
                            Text(appLocalized("Author")).foregroundStyle(.secondary)
                            Text(author).textSelection(.enabled)
                        }
                    }
                    if let version = metadata.version {
                        GridRow {
                            Text(appLocalized("Version")).foregroundStyle(.secondary)
                            Text(version).textSelection(.enabled)
                        }
                    }
                    if let license = metadata.license {
                        GridRow {
                            Text(appLocalized("License")).foregroundStyle(.secondary)
                            Text(license).textSelection(.enabled)
                        }
                    }
                }
                .font(.subheadline)

                SkillFrontmatterView(fields: extraFields, title: nil)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLocalized("Actions"))
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
                            systemImage: viewModel.detailInstallButtonSystemImage(for: skill)
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)

                Button {
                    NSWorkspace.shared.open(detailPageURL)
                } label: {
                    Label(appLocalized("View on ClawHub"), systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }

            MarketplaceInstallTargetsView(
                agentTypes: viewModel.targetAgentTypes,
                selectedAgents: viewModel.selectedTargetAgents,
                selectionSummary: viewModel.targetSelectionSummary(),
                noteText: appLocalized("Skills are first written into the SkillsMaster canonical directory, then materialized as direct installs using each Agent's default install mode."),
                isAgentDetected: viewModel.isAgentDetected(_:),
                onToggle: viewModel.toggleTargetAgent(_:)
            )
        }
    }

    private var skillContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLocalized("Skill Content"))
                .font(.headline)

            if viewModel.isLoadingContent {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appLocalized("Loading SKILL.md from ClawHub..."))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.contentError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    Button {
                        NSWorkspace.shared.open(detailPageURL)
                    } label: {
                        Label(appLocalized("View on ClawHub instead"), systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
            } else if let content = viewModel.fetchedContent {
                if !content.markdownBody.isEmpty {
                    MarkdownContentView(
                        markdownText: content.markdownBody,
                        translationScope: .clawHub,
                        manuallyShowsChineseTranslation: viewModel.isShowingManualTranslation(for: skill.id)
                    )
                } else {
                    Text(appLocalized("No content available."))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .italic()
                }
            }
        }
    }

    private var ownerText: String? {
        let handle = viewModel.selectedSkillDetail?.skill.ownerHandle ?? skill.ownerHandle
        let displayName = viewModel.selectedSkillDetail?.skill.ownerDisplayName ?? skill.ownerDisplayName

        switch (handle, displayName) {
        case let (handle?, displayName?) where !displayName.isEmpty && displayName.caseInsensitiveCompare(handle) != .orderedSame:
            return "@\(handle) (\(displayName))"
        case let (handle?, _):
            return "@\(handle)"
        case let (_, displayName?) where !displayName.isEmpty:
            return displayName
        default:
            return nil
        }
    }

    private var moderationText: String? {
        guard let detail = viewModel.selectedSkillDetail else { return nil }

        switch (detail.moderationVerdict, detail.moderationSummary) {
        case let (verdict?, summary?) where !summary.isEmpty:
            return "\(verdict): \(summary)"
        case let (verdict?, _):
            return verdict
        case let (_, summary?) where !summary.isEmpty:
            return summary
        default:
            return nil
        }
    }

    private var detailPageURL: URL {
        viewModel.selectedSkillDetail?.skill.browserURL ?? skill.browserURL
    }
}
