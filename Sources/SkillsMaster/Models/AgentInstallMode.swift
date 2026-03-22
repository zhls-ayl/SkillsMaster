import Foundation

/// AgentInstallMode describes how SkillsMaster materializes a managed skill
/// into an Agent's own skills directory.
enum AgentInstallMode: String, CaseIterable, Identifiable, Codable {
    case symlink
    case copy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .symlink: "软链接"
        case .copy: "物理复制"
        }
    }

    var detailText: String {
        switch self {
        case .symlink: "在 Agent 目录中创建 symbolic link，指向事实源目录"
        case .copy: "把事实源目录实际复制到 Agent 目录，并在更新时同步覆盖"
        }
    }
}
