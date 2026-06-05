import SwiftUI

/// AllSkillsView is the main installed skill list page (F02)
///
/// Displays all installed skills, supporting search, filtering, and sorting
struct AllSkillsView: View {

    /// @Bindable allows @Observable object properties to be prefixed with $ to create Binding
    /// For example, $viewModel.searchText creates a Binding<String>
    @Bindable var viewModel: AllSkillsViewModel
    @Binding var selectedSkillID: String?
    /// Agent filter driven by sidebar selection in ContentView.
    /// Keeping this as an input value preserves one-way data flow from navigation state to list rendering.
    let selectedAgentFilter: AgentType?
    @Environment(SkillManager.self) private var skillManager

    /// Persisted set of expanded category names. Loaded from UserDefaults on init,
    /// saved on change. Empty by default (all categories start collapsed).
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        // Compute once per render pass to avoid recalculating filter/sort logic in multiple branches.
        let groups = viewModel.groupedSkills(agentFilter: selectedAgentFilter)
        let filteredSkills = groups.flatMap(\.skills)
        Group {
            if skillManager.isLoading && skillManager.skills.isEmpty {
                // Show progress indicator on first load
                ProgressView(AppLocalization.string("Scanning skills..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSkills.isEmpty {
                // Empty state
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: AppLocalization.string("No Skills Found"),
                    subtitle: viewModel.searchText.isEmpty
                        ? AppLocalization.string("Install skills using npx skills add or the CLI")
                        : AppLocalization.string("No skills match your search")
                )
            } else {
                // ScrollView avoids NSTableView reentrant/out-of-bounds
                // warnings that List + DisclosureGroup triggers on macOS.
                skillListView(groups: groups)
            }
        }
        .navigationTitle(navigationTitle)
        .searchable(text: $viewModel.searchText, prompt: AppLocalization.string("Search skills..."))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    Section(AppLocalization.string("Sort By")) {
                        ForEach(AllSkillsViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                if viewModel.sortOrder == order {
                                    viewModel.sortDirection = viewModel.sortDirection.toggled
                                } else {
                                    viewModel.sortOrder = order
                                    viewModel.sortDirection = .ascending
                                }
                            } label: {
                                HStack {
                                    Label(order.displayName, systemImage: order.iconName)
                                    if viewModel.sortOrder == order {
                                        Spacer()
                                        Image(systemName: viewModel.sortDirection.iconName)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(viewModel.sortOrder.displayName)
                        Image(systemName: viewModel.sortDirection.iconName)
                            .font(.caption2)
                            .imageScale(.small)
                    }
                }
            }
        }
        .alert(AppLocalization.string("Delete Skill"), isPresented: $viewModel.showDeleteConfirmation) {
            Button(AppLocalization.string("Cancel"), role: .cancel) {
                viewModel.cancelDelete()
            }
            Button(AppLocalization.string("Delete"), role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            if let skill = viewModel.skillToDelete {
                Text(AppLocalization.format(
                    "Are you sure you want to delete \"%@\"? This will remove the Skill directory and all Agent assignments (symbolic links or physical copies), and cannot be undone.",
                    skill.displayName
                ))
            }
        }
        .overlay(alignment: .bottom) {
            if let error = skillManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                    Spacer()
                    Button(AppLocalization.string("Dismiss")) {
                        skillManager.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(.red.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }
        }
        .onAppear {
            expandedCategories = loadExpansionState()
        }
    }

    private var navigationTitle: String {
        if let agent = selectedAgentFilter {
            return agent.displayName
        }
        return AppLocalization.string("All Skills")
    }

    /// Renders the skill list using ScrollView + LazyVStack to avoid NSTableView
    /// reentrant/out-of-bounds warnings inherent to List + DisclosureGroup on macOS.
    @ViewBuilder
    private func skillListView(groups: [AllSkillsViewModel.SkillCategoryGroup]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    if let category = group.category {
                        DisclosureGroup(isExpanded: expansionBinding(for: category)) {
                            ForEach(group.skills) { skill in
                                skillRow(skill)
                            }
                        } label: {
                            HStack {
                                Text(category)
                                    .fontWeight(.semibold)
                                Text("(\(group.skills.count))")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .padding(.horizontal, 8)
                        Divider()
                    } else {
                        ForEach(group.skills) { skill in
                            skillRow(skill)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        SkillRowView(skill: skill)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(selectedSkillID == skill.id
                ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 8)
            .onTapGesture {
                selectedSkillID = skill.id
            }
            .contextMenu {
                Button(AppLocalization.string("Open in Finder")) {
                    ApplicationLauncher.revealInFinder(itemURL: skill.canonicalURL)
                }
                Divider()
                Button(AppLocalization.string("Delete"), role: .destructive) {
                    viewModel.requestDelete(skill: skill)
                }
            }
    }

    // MARK: - Expansion state with persistence

    private func expansionBinding(for category: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { newValue in
                if newValue {
                    expandedCategories.insert(category)
                } else {
                    expandedCategories.remove(category)
                }
                saveExpansionState()
            }
        )
    }

    private func loadExpansionState() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: expansionDefaultsKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveExpansionState() {
        if let data = try? JSONEncoder().encode(expandedCategories) {
            UserDefaults.standard.set(data, forKey: expansionDefaultsKey)
        }
    }

    private let expansionDefaultsKey = "skillCategoryExpansion"
}
