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
            self == .ascending ? "升序" : "降序"
        }
    }

    /// Sort order enum
    enum SortOrder: String, CaseIterable {
        case name = "名称"
        case scope = "作用域"
        case agent = "Agent 数量"

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
            skillManager.errorMessage = "删除失败：\(error.localizedDescription)"
        }
        skillToDelete = nil
        showDeleteConfirmation = false
    }

    /// Cancels deletion
    func cancelDelete() {
        skillToDelete = nil
        showDeleteConfirmation = false
    }
}
