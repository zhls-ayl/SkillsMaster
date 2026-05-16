import SwiftUI

/// AgentToggleView displays installation status toggles for skill on each Agent (F06)
///
/// Design principles:
/// - Each Agent only manages its own directory's direct install (Toggle ON = create, OFF = remove)
/// - Cross-directory reading is each Agent's own runtime mechanism — SkillsMaster does not interfere
/// - Inheritance hints are always shown (regardless of toggle state) to inform users
///   that an Agent may still read the skill via another directory even after toggle OFF
/// - Agents are grouped by vendor using AgentGroup, with select-all/remove-all per group
struct AgentToggleView: View {

    let skill: Skill
    let viewModel: SkillDetailViewModel
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AgentGroup.allCases) { group in
                groupSection(group)
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: AgentGroup) -> some View {
        let isOperating = viewModel.batchOperatingGroups.contains(group) || viewModel.isGlobalBatchOperating

        let hasSelectableAgent = group.sortedAgents.contains { agent in
            // Available for batch select if not yet directly installed (regardless of CLI availability).
            !skill.installations.contains { $0.agentType == agent && !$0.isInherited }
        }

        let hasRemovableAgent = group.sortedAgents.contains { agent in
            skill.installations.contains { $0.agentType == agent && !$0.isInherited }
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                if viewModel.batchOperatingGroups.contains(group) {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button {
                    Task { await viewModel.selectAllAgents(in: group, for: skill) }
                } label: {
                    Label(appLocalized("Select All"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(appLocalized("Assign skill to all agents in this group"))
                .disabled(!hasSelectableAgent || isOperating)

                Button {
                    Task { await viewModel.removeAllAgents(in: group, for: skill) }
                } label: {
                    Label(appLocalized("Remove All"), systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .help(appLocalized("Remove skill from all agents in this group"))
                .disabled(!hasRemovableAgent || isOperating)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(group.sortedAgents) { agentType in
                    AgentToggleRow(
                        agentType: agentType,
                        skill: skill,
                        viewModel: viewModel,
                        skillManager: skillManager,
                        inheritancePaths: inheritanceDisplayPaths(for: agentType),
                        isBatchDisabled: isOperating
                    )
                }
            }
        }
    }

    /// Get display paths where this Agent can additionally read the given skill.
    private func inheritanceDisplayPaths(for agentType: AgentType) -> [String] {
        var paths: [String] = []
        for dir in agentType.additionalReadableSkillsDirectories {
            let skillURL = dir.url.appendingPathComponent(skill.id)
            guard FileManager.default.fileExists(atPath: skillURL.path) else { continue }

            if SymlinkManager.matchesCanonicalSkill(at: skillURL, canonicalURL: skill.canonicalURL) {
                let displayPath = NSString(string: dir.url.path).abbreviatingWithTildeInPath as String
                paths.append(displayPath)
            }
        }
        return paths
    }
}

/// Card-style Agent selector row.
///
/// Reads installation state directly from the model (no local @State) so the UI
/// updates immediately when `skillManager.skills` changes during batch operations.
/// Tapping the card triggers the per-agent toggle action.
private struct AgentToggleRow: View {

    let agentType: AgentType
    let skill: Skill
    let viewModel: SkillDetailViewModel
    let skillManager: SkillManager
    let inheritancePaths: [String]
    let isBatchDisabled: Bool

    /// Derive `isOn` directly from the model on every render.
    /// `skillManager` is `@Observable`, so when `skillManager.skills` updates,
    /// SwiftUI re-renders this row and `isOn` reflects the latest state immediately.
    private var isOn: Bool {
        // Prefer the latest skill from the manager to avoid stale struct copies during batch loops.
        let currentSkill = skillManager.skills.first { $0.id == skill.id } ?? skill
        return currentSkill.installations.contains {
            $0.agentType == agentType && !$0.isInherited
        }
    }

    private var agent: Agent? {
        skillManager.agents.first { $0.type == agentType }
    }

    private var isAgentAvailable: Bool {
        agent?.isInstalled == true || agent?.configDirectoryExists == true
    }

    private var isInteractive: Bool {
        // Always allow toggle ON to pre-install for agents the user might install later;
        // also allow toggle OFF for already-on rows.
        !isBatchDisabled
    }

    var body: some View {
        Button {
            Task { await viewModel.toggleAgent(agentType, for: skill) }
        } label: {
            HStack(spacing: 8) {
                AgentIconView(agentType: agentType, size: 18)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agentType.displayName)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !inheritancePaths.isEmpty {
                        Text(AppLocalization.format("Also reads %@", inheritancePaths.joined(separator: ", ")))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !isAgentAvailable && !isOn {
                        Text(appLocalized("Not installed"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.6))
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .opacity(isAgentAvailable || isOn ? 1.0 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .help(toolTipText)
    }

    private var toolTipText: String {
        if !isAgentAvailable && !isOn {
            return AppLocalization.format("%@ is not installed on this system", agentType.displayName)
        }
        return isOn
            ? AppLocalization.format("Click to remove from %@", agentType.displayName)
            : AppLocalization.format("Click to assign to %@", agentType.displayName)
    }
}
