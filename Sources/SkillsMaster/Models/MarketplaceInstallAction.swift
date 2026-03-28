import Foundation

/// Unified action label for marketplace and repository detail installs.
enum MarketplaceInstallAction {
    case install
    case reinstall
    case mixed

    var title: String {
        switch self {
        case .install:
            AppLocalization.string("Install")
        case .reinstall:
            AppLocalization.string("Reinstall")
        case .mixed:
            AppLocalization.string("Install / Reinstall")
        }
    }

    var completionTitle: String {
        switch self {
        case .install:
            AppLocalization.string("Install Complete")
        case .reinstall:
            AppLocalization.string("Reinstall Complete")
        case .mixed:
            AppLocalization.string("Install / Reinstall Complete")
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
