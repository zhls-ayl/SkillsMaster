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

    var body: some View {
        // Compute once per render pass to avoid recalculating filter/sort logic in multiple branches.
        let filteredSkills = viewModel.filteredSkills(agentFilter: selectedAgentFilter)
        Group {
            if skillManager.isLoading && skillManager.skills.isEmpty {
                // Show progress indicator on first load
                ProgressView("Scanning skills...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSkills.isEmpty {
                // Empty state
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Skills Found",
                    subtitle: viewModel.searchText.isEmpty
                        ? "Install skills using npx skills add or the CLI"
                        : "No skills match your search"
                )
            } else {
                // Skill list
                List(filteredSkills, selection: $selectedSkillID) { skill in
                    SkillRowView(skill: skill)
                        .tag(skill.id)
                        // contextMenu is macOS's right-click menu
                        .contextMenu {
                            Button("Open in Finder") {
                                ApplicationLauncher.revealInFinder(itemURL: skill.canonicalURL)
                            }
                            Divider()  // Menu separator
                            Button("Delete", role: .destructive) {
                                viewModel.requestDelete(skill: skill)
                            }
                        }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle(navigationTitle)
        // Search bar (macOS standard search field, displayed in toolbar)
        .searchable(text: $viewModel.searchText, prompt: "Search skills...")
        // Toolbar: sorting and filtering
        .toolbar {
            // placement: .navigation places toolbar items on the left (navigation area), default .automatic places on right
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    // Section creates titled groups in menus, similar to Android's menu group
                    Section("Sort By") {
                        ForEach(AllSkillsViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                if viewModel.sortOrder == order {
                                    // Click selected sort field → toggle ascending/descending
                                    viewModel.sortDirection = viewModel.sortDirection.toggled
                                } else {
                                    // Click new sort field → switch to that field, reset to ascending
                                    viewModel.sortOrder = order
                                    viewModel.sortDirection = .ascending
                                }
                            } label: {
                                // HStack horizontal layout: icon + text + sort direction arrow
                                HStack {
                                    Label(order.displayName, systemImage: order.iconName)
                                    if viewModel.sortOrder == order {
                                        // Spacer pushes arrow to the right
                                        Spacer()
                                        Image(systemName: viewModel.sortDirection.iconName)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    // Toolbar button appearance: sort icon + current sort field + direction arrow
                    // Label provides both text and icon, macOS toolbar decides which to display based on space
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(viewModel.sortOrder.displayName)
                        Image(systemName: viewModel.sortDirection.iconName)
                            .font(.caption2)
                            // imageScale controls SF Symbol size
                            .imageScale(.small)
                    }
                }
            }
        }
        // Delete confirmation dialog
        // .alert similar to Android's AlertDialog or Web's confirm()
        .alert("Delete Skill", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                Task { await viewModel.confirmDelete() }
            }
        } message: {
            if let skill = viewModel.skillToDelete {
                Text("Are you sure you want to delete \"\(skill.displayName)\"吗？这会删除该 Skill 目录及其全部 Agent 分配（软链接或物理复制），且无法撤销。")
            }
        }
        // Error message
        .overlay(alignment: .bottom) {
            if let error = skillManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                    Spacer()
                    Button("Dismiss") {
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
    }

    private var navigationTitle: String {
        if let agent = selectedAgentFilter {
            return agent.displayName
        }
        return "All Skills"
    }
}
