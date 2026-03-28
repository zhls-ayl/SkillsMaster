import SwiftUI

/// AgentToggleView displays installation status toggles for skill on each Agent (F06)
///
/// Design principles:
/// - Each Agent only manages its own directory's direct install (Toggle ON = create, OFF = remove)
/// - Cross-directory reading is each Agent's own runtime mechanism — SkillsMaster does not interfere
/// - Inheritance hints are always shown (regardless of toggle state) to inform users
///   that an Agent may still read the skill via another directory even after toggle OFF
struct AgentToggleView: View {

    let skill: Skill
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AgentType.allCases) { agentType in
                // Each row is a separate subview with its own @State for toggle binding.
                // This avoids the SwiftUI issue where a `let` captured by a Binding closure
                // doesn't reflect @State changes, causing the toggle to "bounce back".
                AgentToggleRow(
                    agentType: agentType,
                    skill: skill,
                    viewModel: viewModel,
                    skillManager: skillManager,
                    inheritancePaths: inheritanceDisplayPaths(for: agentType)
                )
            }
        }
    }

    /// Get display paths where this Agent can additionally read the given skill.
    ///
    /// Checks each directory in the Agent's additionalReadableSkillsDirectories to see
    /// if the skill exists there (either directly or via symbolic link pointing to the same canonical path).
    /// Returns abbreviated paths like "~/.claude/skills" for UI display.
    private func inheritanceDisplayPaths(for agentType: AgentType) -> [String] {
        var paths: [String] = []
        for dir in agentType.additionalReadableSkillsDirectories {
            let skillURL = dir.url.appendingPathComponent(skill.id)
            // Check if the skill exists in this additional directory
            guard FileManager.default.fileExists(atPath: skillURL.path) else { continue }

            // Verify it resolves to the same canonical skill (or is a synced physical copy of it)
            if SymlinkManager.matchesCanonicalSkill(at: skillURL, canonicalURL: skill.canonicalURL) {
                // NSString.abbreviatingWithTildeInPath replaces home directory prefix with ~
                let displayPath = NSString(string: dir.url.path).abbreviatingWithTildeInPath as String
                paths.append(displayPath)
            }
        }
        return paths
    }
}

/// Individual toggle row for a single Agent.
///
/// Extracted as a separate view so each row has its own `@State isOn` property.
/// Uses a **custom Binding** to distinguish user-initiated toggles from model syncs:
///
/// - Toggle's Binding `set`: Only called when the USER physically flips the toggle control.
///   SwiftUI's Toggle only invokes the binding setter on user interaction, never on
///   programmatic @State changes. This is the key insight that makes this pattern safe.
/// - `.onChange(of: skill.installations)`: Syncs local @State from the model after
///   refresh() completes, WITHOUT triggering any toggle action.
///
/// Previous approach used `.onChange(of: isOn)` + `isSyncingFromModel` guard flag,
/// which was broken because SwiftUI's `.onChange` fires asynchronously (deferred to the
/// next view update cycle), so the guard flag was already reset to false when the
/// onChange closure ran. This caused FileSystemWatcher-triggered refreshes to create
/// spurious toggle tasks that re-created symbolic links the user had just removed.
private struct AgentToggleRow: View {

    let agentType: AgentType
    let skill: Skill
    let viewModel: SkillDetailViewModel
    let skillManager: SkillManager
    let inheritancePaths: [String]

    /// Local toggle state — source of truth for the Toggle control.
    /// Initialized from model state, updated on user tap (immediate via custom Binding set),
    /// and synced with model state via `.onChange(of: skill.installations)`.
    @State private var isOn: Bool

    init(agentType: AgentType, skill: Skill, viewModel: SkillDetailViewModel,
         skillManager: SkillManager, inheritancePaths: [String]) {
        self.agentType = agentType
        self.skill = skill
        self.viewModel = viewModel
        self.skillManager = skillManager
        self.inheritancePaths = inheritancePaths
        // Initialize @State from model: true if this agent has a direct (non-inherited) installation
        _isOn = State(initialValue: skill.installations.contains {
            $0.agentType == agentType && !$0.isInherited
        })
    }

    var body: some View {
        let agent = skillManager.agents.first { $0.type == agentType }
        /// Agent is available if its CLI binary is installed or its config directory exists
        let isAgentAvailable = agent?.isInstalled == true || agent?.configDirectoryExists == true

        HStack {
            AgentIconView(agentType: agentType, size: 16)
                .frame(width: 20)

            // Agent name + optional inheritance hint below
            VStack(alignment: .leading, spacing: 2) {
                Text(agentType.displayName)

                // Always show inheritance hint when applicable
                // Informs user that this Agent can read the skill from other directories
                if !inheritancePaths.isEmpty {
                    Text(AppLocalization.format("Also reads %@", inheritancePaths.joined(separator: ", ")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Show "Not installed" for agents that are not available on the system
            if !isAgentAvailable && !isOn {
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Custom Binding: the `set` closure is ONLY called by user interaction with
            // the Toggle control, NOT by programmatic @State changes. This eliminates the
            // race condition where a model-sync @State change could trigger a spurious toggle.
            //
            // When we set `isOn = modelState` in `.onChange(of: skill.installations)`,
            // the Toggle reads the new value via the `get` closure and updates its visual
            // state, but the `set` closure is NOT invoked — only user gestures invoke it.
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    isOn = newValue
                    Task {
                        await viewModel.toggleAgent(agentType, for: skill)
                    }
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                // Only disabled when Agent is not available AND toggle is OFF
                .disabled(!isAgentAvailable && !isOn)
        }
        .padding(.vertical, 2)
        // When model updates (after refresh()), sync local state back from model.
        // This handles both success (state matches) and failure (state reverts).
        // Because we use a custom Binding (not $isOn), changing isOn here does NOT
        // trigger the toggle action — only user interaction with the Toggle control does.
        .onChange(of: skill.installations) {
            let modelState = skill.installations.contains {
                $0.agentType == agentType && !$0.isInherited
            }
            if isOn != modelState {
                isOn = modelState
            }
        }
    }
}
