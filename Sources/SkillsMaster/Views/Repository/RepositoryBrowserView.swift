import SwiftUI

/// RepositoryBrowserView displays skills available in a user-configured custom repository.
///
/// Occupies the "content" (middle) column of NavigationSplitView when a custom repo
/// is selected in the sidebar. The layout and patterns mirror RegistryBrowserView.
///
/// 数据来源：本地已 clone 的 Git repository，路径位于 `~/.skillsmaster/repos/<slug>/`。
/// Skills are discovered by scanning for SKILL.md files — no network requests needed
/// for browsing. A network request (git pull via SSH) only happens on explicit sync.
struct RepositoryBrowserView: View {

    /// ViewModel for this specific repository
    /// @Bindable enables two-way bindings ($viewModel.property) for @Observable classes
    @Bindable var viewModel: RepositoryBrowserViewModel

    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 0) {
            // Repo info header: platform icon + SSH URL + sync status
            repoHeader
            Divider()

            if let notice = viewModel.scanNoticeMessage {
                scanNoticeBanner(message: notice)
                Divider()
            }

            // Main content area
            if viewModel.isLoading && viewModel.allSkills.isEmpty {
                loadingView
            } else if let errorMessage = viewModel.errorMessage, viewModel.allSkills.isEmpty {
                errorView(message: errorMessage)
            } else if viewModel.displayedSkills.isEmpty && !trimmedSearchText.isEmpty {
                // Search is active but no skills match the query
                emptyState
            } else if viewModel.allSkills.isEmpty {
                // Repo is cloned but contains no SKILL.md files (or scan hasn't returned yet)
                noSkillsState
            } else {
                skillList
            }
        }
        // Dynamic navigation title: shows the repo's display name
        .navigationTitle(viewModel.repository.name)
        // Native macOS search bar — filters skill list locally (no network call)
        .searchable(text: $viewModel.searchText, prompt: appLocalized("Filter skills…"))
        // Toolbar: Sync button
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.sync() }
                } label: {
                    if viewModel.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help(appLocalized("Sync repository (git pull)"))
                .disabled(viewModel.isSyncing)
            }
        }
        // Load skills when the view first appears
        .task {
            await viewModel.onAppear()
        }
        // React to sync status transitions from SkillManager.
        // This is the single trigger path for post-sync reload/error presentation.
        .onChange(of: skillManager.repoSyncStatuses[viewModel.repository.id]) { _, newStatus in
            Task { await viewModel.handleSyncStatusChange(newStatus) }
        }
        .alert(item: $viewModel.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(appLocalized("OK")))
            )
        }
    }

    // MARK: - Sub-views

    /// Header showing repository metadata and last sync time
    private var repoHeader: some View {
        HStack(spacing: 8) {
            // Platform icon
            Image(systemName: viewModel.repository.platform.iconName)
                .foregroundStyle(.secondary)

            // Repository URL (truncated in the middle to fit)
            Text(viewModel.repository.repoURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if viewModel.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appLocalized("Syncing..."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(appLocalized("Sync Now")) {
                    Task { await viewModel.sync() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Last synced timestamp
            if let date = viewModel.repository.effectiveLastSyncedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(AppLocalization.format("Synced %@", gitStyleRelativeTime(from: date, now: context.date)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .help(absoluteDateText(date))
            } else {
                Text(appLocalized("Never synced"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Loading spinner for initial load
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(viewModel.loadingMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Error state view (e.g., "not yet synced")
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)

            // Offer to sync immediately
            Button(appLocalized("Sync Now")) {
                Task { await viewModel.sync() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isSyncing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanNoticeBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.06))
    }

    /// State when the repository is cloned but contains no SKILL.md files
    private var noSkillsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(appLocalized("No Skills Found"))
                .font(.headline)
            Text(appLocalized("This repository contains no SKILL.md files."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Empty state when search returns no results
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(AppLocalization.format("No skills match \"%@\"", trimmedSearchText))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trimmedSearchText: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact relative time style similar to git UIs (e.g. "3m ago", "2h ago", "yesterday").
    private func gitStyleRelativeTime(from date: Date, now: Date) -> String {
        AppLocalization.relativeDateTime(from: date, to: now)
    }

    /// Full timestamp shown on hover so users can inspect exact sync time.
    private func absoluteDateText(_ date: Date) -> String {
        AppLocalization.absoluteDateTime(date)
    }

    /// Scrollable list of skills
    private var skillList: some View {
        List(selection: $viewModel.selectedSkillID) {
            ForEach(viewModel.displayedSkills) { skill in
                // Each row is a button that selects the skill for the detail pane
                RepositorySkillRowView(
                    skill: skill,
                    isInstalled: viewModel.isInstalled(skill)
                )
                // .tag associates this row with the skill ID for List selection tracking
                .tag(skill.id)
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Repository Skill Row

/// Displays a single skill from a custom repository.
///
/// Shows: skill name, description, and installed badge.
/// The layout is consistent with RegistrySkillRowView.
private struct RepositorySkillRowView: View {

    let skill: GitService.DiscoveredSkill
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Skill info (left side)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Skill display name (fallback to directory id if metadata name is empty)
                    Text(skill.metadata.name.isEmpty ? skill.id : skill.metadata.name)
                        .font(.headline)
                        .lineLimit(1)

                    // "Installed" badge — same green capsule style as RegistrySkillRowView
                    if isInstalled {
                        Text(appLocalized("Installed"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }

                // Description (secondary text)
                if !skill.metadata.description.isEmpty {
                    Text(skill.metadata.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
