import SwiftUI

/// AllSkillsView is the main installed skill list page (F02)
///
/// Displays all installed skills, supporting search, filtering, and sorting
struct AllSkillsView: View {

    @Bindable var viewModel: AllSkillsViewModel
    @Binding var selectedSkillID: String?
    let selectedAgentFilter: AgentType?
    @Environment(SkillManager.self) private var skillManager

    /// Persisted set of expanded category names. Loaded from UserDefaults on init,
    /// saved on change. Empty by default (all categories start collapsed).
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        let groups = viewModel.groupedSkills(agentFilter: selectedAgentFilter)
        let filteredSkills = groups.flatMap(\.skills)
        Group {
            if skillManager.isLoading && skillManager.skills.isEmpty {
                ProgressView(AppLocalization.string("Scanning skills..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSkills.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: AppLocalization.string("No Skills Found"),
                    subtitle: viewModel.searchText.isEmpty
                        ? AppLocalization.string("Install skills using npx skills add or the CLI")
                        : AppLocalization.string("No skills match your search")
                )
            } else {
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

    /// List-based rendering with DisclosureGroup for collapsible categories.
    /// Expansion state changes are deferred to the next runloop tick via
    /// DispatchQueue.main.async to avoid NSTableView reentrant delegate warnings.
    @ViewBuilder
    private func skillListView(groups: [AllSkillsViewModel.SkillCategoryGroup]) -> some View {
        List(selection: $selectedSkillID) {
            ForEach(groups) { group in
                if let category = group.category {
                    DisclosureGroup(isExpanded: expansionBinding(for: category)) {
                        ForEach(group.skills) { skill in
                            skillRow(skill)
                        }
                    } label: {
                        Text("\(category) (\(group.skills.count))")
                            .fontWeight(.semibold)
                    }
                } else {
                    ForEach(group.skills) { skill in
                        skillRow(skill)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func skillRow(_ skill: Skill) -> some View {
        SkillRowView(skill: skill)
            .tag(skill.id)
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
                // Defer to next runloop tick: avoids NSTableView reentrant
                // delegate warnings when DisclosureGroup modifies row count
                // during an active table-view delegate callback.
                DispatchQueue.main.async {
                    if newValue {
                        expandedCategories.insert(category)
                    } else {
                        expandedCategories.remove(category)
                    }
                    saveExpansionState()
                }
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
