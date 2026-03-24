import Foundation

/// Unified action label for marketplace and repository detail installs.
enum MarketplaceInstallAction {
    case install
    case reinstall
    case mixed

    var title: String {
        switch self {
        case .install:
            "Install"
        case .reinstall:
            "Reinstall"
        case .mixed:
            "Install / Reinstall"
        }
    }

    var completionTitle: String {
        switch self {
        case .install:
            "Install Complete"
        case .reinstall:
            "Reinstall Complete"
        case .mixed:
            "Install / Reinstall Complete"
        }
    }

    var systemImage: String {
        switch self {
        case .install:
            "arrow.down.circle"
        case .reinstall, .mixed:
            "arrow.triangle.2.circlepath"
        }
    }

    static func resolve(
        selectedAgents: Set<AgentType>,
        directInstalledAgents: Set<AgentType>,
        fallbackWhenSelectionEmpty: MarketplaceInstallAction
    ) -> MarketplaceInstallAction {
        guard !selectedAgents.isEmpty else {
            return fallbackWhenSelectionEmpty
        }

        let installedSelection = selectedAgents.intersection(directInstalledAgents)
        if installedSelection.isEmpty {
            return .install
        }
        if installedSelection.count == selectedAgents.count {
            return .reinstall
        }
        return .mixed
    }
}
