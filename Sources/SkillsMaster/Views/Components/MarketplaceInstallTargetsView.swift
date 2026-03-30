import SwiftUI

/// Shared Agent selection block for marketplace and repository detail pages.
struct MarketplaceInstallTargetsView: View {
    let agentTypes: [AgentType]
    let selectedAgents: Set<AgentType>
    let selectionSummary: String
    let noteText: String
    let isAgentDetected: (AgentType) -> Bool
    let onToggle: (AgentType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalized("Install Targets"))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(agentTypes) { agentType in
                    Toggle(isOn: Binding(
                        get: { selectedAgents.contains(agentType) },
                        set: { _ in onToggle(agentType) }
                    )) {
                        HStack(spacing: 6) {
                            AgentIconView(agentType: agentType, size: 13)
                            Text(agentType.displayName)
                        }
                        .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .opacity(isAgentDetected(agentType) ? 1.0 : 0.5)
                }
            }

            Text(selectionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(noteText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}
