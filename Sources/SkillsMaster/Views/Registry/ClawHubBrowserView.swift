import SwiftUI
import AppKit

/// ClawHub marketplace page for browsing and searching skills.
struct ClawHubBrowserView: View {
    @Bindable var viewModel: ClawHubBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isSearchActive {
                browseControls
                Divider()
            }

            Group {
                if viewModel.isLoading && viewModel.displayedSkills.isEmpty {
                    loadingView
                } else if viewModel.displayedSkills.isEmpty {
                    emptyState
                } else {
                    skillList
                }
            }
        }
        .navigationTitle("ClawHub")
        .searchable(text: $viewModel.searchText, prompt: "Search ClawHub skills...")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.onSearchTextChanged()
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新 ClawHub 列表")
            }

            ToolbarItem {
                Button {
                    if let url = URL(string: "https://clawhub.ai") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .help("在浏览器打开 ClawHub")
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .alert(item: $viewModel.notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var browseControls: some View {
        ViewThatFits(in: .horizontal) {
            expandedBrowseControls
            compactBrowseControls
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var expandedBrowseControls: some View {
        HStack(spacing: 4) {
            sortControls

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            directionControls

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            filterControls
            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var compactBrowseControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ClawHubService.SkillSort.allCases) { sort in
                    Button {
                        viewModel.selectSort(sort)
                    } label: {
                        menuRowLabel(
                            title: sort.displayName,
                            systemImage: sortIconName(sort),
                            isSelected: viewModel.selectedSort == sort
                        )
                    }
                }
            } label: {
                compactMenuChip(
                    title: viewModel.selectedSort.displayName,
                    systemImage: sortIconName(viewModel.selectedSort),
                    isSelected: true
                )
            }

            Menu {
                ForEach(ClawHubService.SortDirection.allCases) { direction in
                    Button {
                        viewModel.selectDirection(direction)
                    } label: {
                        menuRowLabel(
                            title: direction.displayName,
                            systemImage: direction == .descending ? "arrow.down" : "arrow.up",
                            isSelected: viewModel.selectedDirection == direction
                        )
                    }
                }
            } label: {
                compactMenuChip(
                    title: viewModel.selectedDirection.displayName,
                    systemImage: viewModel.selectedDirection == .descending ? "arrow.down" : "arrow.up",
                    isSelected: true
                )
            }

            Menu {
                Button {
                    viewModel.toggleHighlightedOnly()
                } label: {
                    menuRowLabel(title: "Highlighted", systemImage: "sparkles", isSelected: viewModel.highlightedOnly)
                }

                Button {
                    viewModel.toggleNonSuspiciousOnly()
                } label: {
                    menuRowLabel(title: "Safe Only", systemImage: "checkmark.shield", isSelected: viewModel.nonSuspiciousOnly)
                }
            } label: {
                compactMenuChip(
                    title: compactFilterTitle,
                    systemImage: compactFilterIconName,
                    isSelected: viewModel.highlightedOnly || viewModel.nonSuspiciousOnly
                )
            }

            Spacer(minLength: 0)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var sortControls: some View {
        HStack(spacing: 4) {
            ForEach(ClawHubService.SkillSort.allCases) { sort in
                controlChip(isSelected: viewModel.selectedSort == sort) {
                    viewModel.selectSort(sort)
                } label: {
                    Label(sort.displayName, systemImage: sortIconName(sort))
                }
            }
        }
    }

    private var directionControls: some View {
        HStack(spacing: 4) {
            ForEach(ClawHubService.SortDirection.allCases) { direction in
                controlChip(isSelected: viewModel.selectedDirection == direction) {
                    viewModel.selectDirection(direction)
                } label: {
                    Label(
                        direction.displayName,
                        systemImage: direction == .descending ? "arrow.down" : "arrow.up"
                    )
                }
            }
        }
    }

    private var filterControls: some View {
        HStack(spacing: 4) {
            controlChip(isSelected: viewModel.highlightedOnly) {
                viewModel.toggleHighlightedOnly()
            } label: {
                Label("Highlighted", systemImage: "sparkles")
            }

            controlChip(isSelected: viewModel.nonSuspiciousOnly) {
                viewModel.toggleNonSuspiciousOnly()
            } label: {
                Label("Safe Only", systemImage: "checkmark.shield")
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(viewModel.isSearchActive ? "正在搜索 ClawHub..." : "正在加载 ClawHub skills...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var skillList: some View {
        List(selection: $viewModel.selectedSkillID) {
            ForEach(viewModel.displayedSkills) { skill in
                ClawHubSkillRowView(
                    skill: skill,
                    isInstalled: viewModel.isInstalled(skill),
                    isInstalling: viewModel.isInstalling(skill),
                    onInstall: { viewModel.installSkill(skill) }
                )
                .tag(skill.id)
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(after: skill.id) }
                }
            }

            if viewModel.isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载更多...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } else if let loadMoreErrorMessage = viewModel.loadMoreErrorMessage {
                VStack(spacing: 6) {
                    Text("加载更多失败")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(loadMoreErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await viewModel.retryLoadMore() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private var emptyState: some View {
        if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("加载 ClawHub 失败")
                    .font(.title3)
                    .fontWeight(.medium)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isSearchActive {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "无结果",
                subtitle: "没有匹配 \"\(viewModel.searchText)\" 的 ClawHub skill"
            )
        } else {
            EmptyStateView(
                icon: "shippingbox",
                title: "暂无 Skills",
                subtitle: "ClawHub 当前没有返回可展示的 skills"
            )
        }
    }

    @ViewBuilder
    private func controlChip<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func compactMenuChip(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    @ViewBuilder
    private func menuRowLabel(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var compactFilterTitle: String {
        switch (viewModel.highlightedOnly, viewModel.nonSuspiciousOnly) {
        case (false, false): return "Filters"
        case (true, false): return "Highlighted"
        case (false, true): return "Safe Only"
        case (true, true): return "Highlighted + Safe"
        }
    }

    private var compactFilterIconName: String {
        viewModel.highlightedOnly || viewModel.nonSuspiciousOnly
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private func sortIconName(_ sort: ClawHubService.SkillSort) -> String {
        switch sort {
        case .downloads: return "arrow.down.circle"
        case .newest: return "sparkles"
        case .updated: return "clock.arrow.circlepath"
        case .installs: return "square.and.arrow.down"
        case .stars: return "star"
        case .name: return "textformat.abc"
        }
    }
}

private struct ClawHubSkillRowView: View {
    let skill: ClawHubSkill
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.headline)

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

                    Text(skill.descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button(isInstalling ? "Installing..." : "Install") {
                    onInstall()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isInstalled || isInstalling)
            }

            HStack(spacing: 12) {
                Label(skill.formattedDownloads, systemImage: "arrow.down.circle")
                Label(skill.formattedStars, systemImage: "star")

                if let version = skill.latestVersion {
                    Label(version, systemImage: "tag")
                }

                if let updatedDate = skill.formattedUpdatedDate {
                    Label(updatedDate, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
