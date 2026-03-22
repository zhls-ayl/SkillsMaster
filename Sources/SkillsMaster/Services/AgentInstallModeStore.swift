import Foundation

/// Persists per-Agent default install mode in UserDefaults.
final class AgentInstallModeStore {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAll() -> [AgentType: AgentInstallMode] {
        Dictionary(uniqueKeysWithValues: AgentType.allCases.map { agent in
            (agent, mode(for: agent))
        })
    }

    func mode(for agent: AgentType) -> AgentInstallMode {
        guard let rawValue = defaults.string(forKey: key(for: agent)),
              let mode = AgentInstallMode(rawValue: rawValue) else {
            return .symlink
        }
        return mode
    }

    func setMode(_ mode: AgentInstallMode, for agent: AgentType) {
        defaults.set(mode.rawValue, forKey: key(for: agent))
    }

    private func key(for agent: AgentType) -> String {
        "\(Constants.agentInstallModeKeyPrefix).\(agent.rawValue)"
    }
}
