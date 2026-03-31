import SwiftUI

/// RepositorySkillDetailView renders detail content for a selected skill from a custom repository.
///
/// Shown in the right pane of NavigationSplitView when user selects a row in RepositoryBrowserView.
/// Full SKILL.md content is loaded lazily from the local clone only for the selected item.
struct RepositorySkillDetailView: View {

    let skill: GitService.DiscoveredSkill
    let repository: SkillRepository
    let viewModel: RepositoryBrowserViewModel
    let content: SkillMDParser.ParseResult?
    let isLoadingContent: Bool
    let contentError: String?
    let isInstalled: Bool
    let onInstall: () -> Void
    let onLoadContent: () async -> Void

    private var displayMetadata: SkillMetadata {
        content?.metadata ?? skill.metadata
    }

    private var displayName: String {
        displayMetadata.name.isEmpty ? skill.id : displayMetadata.name
    }

    private var headerDescriptionText: String {
        FrontmatterDisplay.value(for: "description", in: content?.frontmatterText ?? "")
            ?? displayMetadata.description
    }

    private var extraFrontmatterFields: [FrontmatterField] {
        FrontmatterDisplay.extraFields(
            from: content?.frontmatterText ?? "",
            excluding: ["name", "description", "license"]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Divider()

                metadataSection

                if !extraFrontmatterFields.isEmpty {
                    Divider()
                    SkillFrontmatterView(fields: extraFrontmatterFields)
                }

                Divider()

                actionsSection

                Divider()

                markdownSection
            }
            .padding()
        }
        .navigationTitle(displayName)
        .task(id: skill.id) {
            await onLoadContent()
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

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayName)
                    .font(.title)
                    .fontWeight(.bold)
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
                Text(appLocalized("ID:"))
                    .foregroundStyle(.secondary)
                Text(skill.id)
                    .textSelection(.enabled)
            }
            .font(.subheadline)

            if !headerDescriptionText.isEmpty {
                SkillDescriptionText(
                    text: headerDescriptionText,
                    font: .body,
                    isSelectable: true
                )
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalized("Metadata"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(appLocalized("Repository")).foregroundStyle(.secondary)
                    Text(repository.name).textSelection(.enabled)
                }
                GridRow {
                    Text(appLocalized("Path")).foregroundStyle(.secondary)
                    Text(skill.skillMDPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let author = displayMetadata.author {
                    GridRow {
                        Text(appLocalized("Author")).foregroundStyle(.secondary)
                        Text(author).textSelection(.enabled)
                    }
                }
                if let version = displayMetadata.version {
                    GridRow {
                        Text(appLocalized("Version")).foregroundStyle(.secondary)
                        Text(version).textSelection(.enabled)
                    }
                }
                if let license = displayMetadata.license {
                    GridRow {
                        Text(appLocalized("License")).foregroundStyle(.secondary)
                        Text(license).textSelection(.enabled)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalized("Actions"))
                .font(.headline)

            Button {
                onInstall()
            } label: {
                if viewModel.isInstalling(skill) {
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
            .disabled(viewModel.isInstalling(skill) || !viewModel.canInstallFromLocal)
            .help(installHelpText)

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

    @ViewBuilder
    private var markdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalized("Skill Content"))
                .font(.headline)

            if isLoadingContent {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appLocalized("Loading SKILL.md…"))
                        .foregroundStyle(.secondary)
                }
            } else if let contentError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(contentError)
                        .foregroundStyle(.secondary)
                    Button(appLocalized("Retry Loading")) {
                        Task { await onLoadContent() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if let markdownBody = content?.markdownBody, !markdownBody.isEmpty {
                MarkdownContentView(
                    markdownText: markdownBody,
                    translationScope: .repositories,
                    manuallyShowsChineseTranslation: viewModel.isShowingManualTranslation(for: skill.id)
                )
            } else {
                Text(appLocalized("No markdown content available in this SKILL.md."))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }

    private var installHelpText: String {
        if let installDisabledReason = viewModel.installDisabledReason { return installDisabledReason }
        if repository.isLocalCollection {
            return appLocalized("Install this imported local skill to the selected Agents")
        }
        return appLocalized("Install this skill from the local repository clone")
    }
}
