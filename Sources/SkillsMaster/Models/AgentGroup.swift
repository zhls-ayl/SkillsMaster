import Foundation

/// AgentGroup represents vendor/company groupings for AI code assistants.
/// Each AgentType belongs to exactly one group. The rawValue defines display order.
enum AgentGroup: Int, CaseIterable, Identifiable, Hashable {
    case anthropic = 0
    case openAI = 1
    case google = 2
    case gitHub = 3
    case cursor = 4
    case aws = 5
    case tencent = 6
    case byteDance = 7
    case independent = 8

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .google: "Google"
        case .gitHub: "GitHub"
        case .cursor: "Cursor"
        case .aws: "AWS"
        case .tencent: "Tencent"
        case .byteDance: "ByteDance"
        case .independent: "Independent"
        }
    }

    /// Agents belonging to this group, defined via exhaustive switch to ensure compile-time completeness.
    var agents: [AgentType] {
        switch self {
        case .anthropic: [.claudeCode]
        case .openAI: [.codex]
        case .google: [.geminiCLI, .antigravity]
        case .gitHub: [.githubCopilot]
        case .cursor: [.cursor]
        case .aws: [.kiroCLI]
        case .tencent: [.codeBuddy, .workBuddy]
        case .byteDance: [.trae, .traeCN]
        case .independent: [.openCode, .openClaw]
        }
    }

    /// Agents sorted by displayName character count ascending, then localizedStandardCompare ascending.
    var sortedAgents: [AgentType] {
        agents.sorted { lhs, rhs in
            if lhs.displayName.count != rhs.displayName.count {
                return lhs.displayName.count < rhs.displayName.count
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Reverse lookup: find the group that contains the given agent.
    /// Uses exhaustive switch over AgentType to guarantee compile-time completeness.
    static func group(for agent: AgentType) -> AgentGroup {
        switch agent {
        case .claudeCode: .anthropic
        case .codex: .openAI
        case .geminiCLI, .antigravity: .google
        case .githubCopilot: .gitHub
        case .cursor: .cursor
        case .kiroCLI: .aws
        case .codeBuddy, .workBuddy: .tencent
        case .trae, .traeCN: .byteDance
        case .openCode, .openClaw: .independent
        }
    }
}
