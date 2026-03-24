import SwiftUI
import AppKit

/// SkillsHub marketplace page for browsing and searching skills.
struct SkillsHubBrowserView: View {
    @Bindable var viewModel: SkillsHubBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            controlsBar
            Divider()

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
        .navigationTitle("SkillsHub")
        .searchable(text: $viewModel.searchText, prompt: "搜索 SkillsHub skills...")
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
                .help("刷新 SkillsHub 列表")
            }

            ToolbarItem {
                Button {
                    if let url = URL(string: "https://skillhub.tencent.com/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .help("在浏览器打开 SkillsHub")
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

    private var controlsBar: some View {
        ViewThatFits(in: .horizontal) {
            expandedControls
            compactControls
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var expandedControls: some View {
        HStack(spacing: 8) {
            categoryMenu
            sortMenu
            Spacer()
            paginationControls
        }
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                categoryMenu
                sortMenu
                Spacer(minLength: 0)
            }
            paginationControls
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                viewModel.selectCategory(nil)
            } label: {
                menuRowLabel(title: "全部分类", isSelected: viewModel.selectedCategory == nil)
            }

            Divider()

            ForEach(SkillsHubCategory.allCases) { category in
                Button {
                    viewModel.selectCategory(category)
                } label: {
                    menuRowLabel(title: category.displayName, isSelected: viewModel.selectedCategory == category)
                }
            }
        } label: {
            controlChip(
                title: viewModel.selectedCategory?.displayName ?? "全部分类",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SkillsHubService.SkillSort.allCases) { sort in
                Button {
                    viewModel.selectSort(sort)
                } label: {
                    menuRowLabel(title: sort.displayName, isSelected: viewModel.selectedSort == sort)
                }
            }
        } label: {
            controlChip(
                title: "排序: \(viewModel.selectedSort.displayName)",
                systemImage: "arrow.up.arrow.down.circle"
            )
        }
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goToPreviousPage()
            } label: {
                Label("上一页", systemImage: "chevron.left")
            }
            .disabled(viewModel.currentPage <= 1 || viewModel.isLoading)

            Text("第 \(viewModel.currentPage) / \(viewModel.totalPages) 页")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                viewModel.goToNextPage()
            } label: {
                Label("下一页", systemImage: "chevron.right")
            }
            .disabled(viewModel.currentPage >= viewModel.totalPages || viewModel.isLoading)

            if viewModel.totalCount > 0 {
                Text("共 \(viewModel.totalCount) 项")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(viewModel.isSearchActive ? "正在搜索 SkillsHub..." : "正在加载 SkillsHub skills...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        if let errorMessage = viewModel.errorMessage {
            return AnyView(
                VStack(spacing: 10) {
                    Text("加载 SkillsHub 失败")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            )
        }

        return AnyView(
            EmptyStateView(
                icon: "shippingbox",
                title: "没有可展示的 Skill",
                subtitle: viewModel.isSearchActive
                    ? "没有匹配当前搜索词的 SkillsHub skill"
                    : "SkillsHub 当前没有返回可展示的 skill"
            )
        )
    }

    private var skillList: some View {
        List(selection: $viewModel.selectedSkillID) {
            ForEach(viewModel.displayedSkills) { skill in
                SkillsHubSkillRowView(
                    skill: skill,
                    isInstalled: viewModel.isInstalled(skill),
                    isFeatured: viewModel.isFeatured(skill)
                )
                .tag(skill.id)
            }
        }
        .listStyle(.inset)
    }

    private func controlChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())
    }

    private func menuRowLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

private struct SkillsHubSkillRowView: View {
    let skill: SkillsHubSkill
    let isInstalled: Bool
    let isFeatured: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(1)

                    if isFeatured {
                        badge("精选", color: .blue)
                    }

                    if isInstalled {
                        badge("Installed", color: .green)
                    }
                }

                Text(skill.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let category = skill.category {
                        Label(category.displayName, systemImage: "tag")
                    }
                    Label(skill.formattedDownloads, systemImage: "arrow.down.circle")
                    Label(skill.formattedInstalls, systemImage: "square.and.arrow.down")
                    Label(skill.formattedStars, systemImage: "star")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
        }
        .padding(.vertical, 4)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
