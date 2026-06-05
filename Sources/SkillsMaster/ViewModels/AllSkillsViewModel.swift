import Foundation

/// AllSkillsViewModel manages the state and interaction logic for the All Skills page
///
/// In the MVVM architecture, the ViewModel acts as a bridge between View and Model:
/// - View observes ViewModel state changes through data binding
/// - View user actions invoke ViewModel methods
/// - ViewModel calls Service layer to handle business logic
///
/// @Observable enables SwiftUI to automatically track property changes and refresh the UI
/// @MainActor ensures all state modifications happen on the main thread (UI-safe)
@MainActor
@Observable
final class AllSkillsViewModel {

    /// Search keyword
    var searchText = ""

    /// Sort order
    var sortOrder: SortOrder = .name

    /// Sort direction (ascending/descending)
    var sortDirection: SortDirection = .ascending

    /// Currently selected skill (used for navigation to detail page)
    var selectedSkillID: String?

    /// Whether to show delete confirmation dialog
    var showDeleteConfirmation = false

    /// Skill pending deletion
    var skillToDelete: Skill?

    /// Sort direction enum
    /// Swift enums can conform to multiple protocols:
    /// - CaseIterable: provides allCases collection for iterating over enum values
    enum SortDirection: CaseIterable {
        case ascending
        case descending

        /// Toggle sort direction, returning the opposite direction
        var toggled: SortDirection {
            self == .ascending ? .descending : .ascending
        }

        /// SF Symbols icon name: ascending uses up arrow, descending uses down arrow
        var iconName: String {
            self == .ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
        }

        /// Display text
        var displayName: String {
            self == .ascending
                ? AppLocalization.string("Ascending")
                : AppLocalization.string("Descending")
        }
    }

    /// Sort order enum
    enum SortOrder: CaseIterable {
        case name
        case scope
        case agent

        var displayName: String {
            switch self {
            case .name:
                AppLocalization.string("Name")
            case .scope:
                AppLocalization.string("Scope")
            case .agent:
                AppLocalization.string("Agent Count")
            }
        }

        /// Each sort order corresponds to an SF Symbol icon
        var iconName: String {
            switch self {
            case .name: return "textformat.abc"
            case .scope: return "scope"
            case .agent: return "cpu"
            }
        }
    }

    /// Reference to global SkillManager (dependency injection)
    let skillManager: SkillManager

    init(skillManager: SkillManager) {
        self.skillManager = skillManager
    }

    /// Calculate the list of skills to display based on current search, external filter, and sort conditions.
    ///
    /// `agentFilter` is provided by the parent view (ContentView -> AllSkillsView),
    /// which keeps sidebar navigation state as the single source of truth.
    /// This avoids maintaining duplicated filter state inside the ViewModel.
    ///
    /// - Parameter agentFilter: Selected agent type from sidebar (nil means show all)
    /// - Returns: The filtered and sorted skill array for rendering
    func filteredSkills(agentFilter: AgentType?) -> [Skill] {
        var result = skillManager.skills

        // 1. Search filtering
        if !searchText.isEmpty {
            result = skillManager.search(query: searchText)
        }

        // 2. Agent filtering
        if let agent = agentFilter {
            result = result.filter { skill in
                skill.installations.contains { $0.agentType == agent }
            }
        }

        // 3. Sorting (ascending or descending based on sort direction)
        // In Swift closures, $0 and $1 are anonymous parameters, similar to Kotlin's it
        let ascending = sortDirection == .ascending
        switch sortOrder {
        case .name:
            result.sort(by: {
                ascending
                    ? $0.displayName.lowercased() < $1.displayName.lowercased()
                    : $0.displayName.lowercased() > $1.displayName.lowercased()
            })
        case .scope:
            result.sort(by: {
                ascending
                    ? $0.scope.displayName < $1.scope.displayName
                    : $0.scope.displayName > $1.scope.displayName
            })
        case .agent:
            // Agent 数量 defaults to descending (most first) for better visibility
            result.sort(by: {
                ascending
                    ? $0.installations.count < $1.installations.count
                    : $0.installations.count > $1.installations.count
            })
        }

        return result
    }

    /// Requests skill deletion (shows confirmation dialog first)
    func requestDelete(skill: Skill) {
        skillToDelete = skill
        showDeleteConfirmation = true
    }

    /// Confirms deletion
    func confirmDelete() async {
        guard let skill = skillToDelete else { return }
        do {
            try await skillManager.deleteSkill(skill)
        } catch {
            skillManager.errorMessage = AppLocalization.format("Delete failed: %@", error.localizedDescription)
        }
        skillToDelete = nil
        showDeleteConfirmation = false
    }

    /// A group of skills sharing the same category (or nil for uncategorized).
    struct SkillCategoryGroup: Identifiable {
        let category: String?
        let skills: [Skill]
        var id: String { category ?? "__uncategorized__" }

        /// Display title for the group section header.
        var title: String { category ?? AppLocalization.string("Other") }
    }

    /// Groups filtered skills by category for agents with nested skill structures.
    ///
    /// For flat agents (maxSkillScanDepth == 1), returns a single uncategorized group
    /// so the list renders as before. For nested agents like Hermes, skills are grouped
    /// by their parent category directory, with skills having no category placed in "Other".
    func groupedSkills(agentFilter: AgentType?) -> [SkillCategoryGroup] {
        let filtered = filteredSkills(agentFilter: agentFilter)
        let useCategories = filtered.contains { $0.category != nil }

        guard useCategories else {
            return [SkillCategoryGroup(category: nil, skills: filtered)]
        }

        let grouped = Dictionary(grouping: filtered) { $0.category }
        return grouped
            .map { SkillCategoryGroup(category: $0.key, skills: $0.value) }
            .sorted { lhs, rhs in
                // Uncategorized (nil) sorts last; categorized groups sort alphabetically
                switch (lhs.category, rhs.category) {
                case (nil, _): return false
                case (_, nil): return true
                case let (a?, b?): return a.localizedStandardCompare(b) == .orderedAscending
                }
            }
    }

    /// Cancels deletion
    func cancelDelete() {
        skillToDelete = nil
        showDeleteConfirmation = false
    }
}
