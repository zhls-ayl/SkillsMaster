import Foundation

/// AgentInstallMode describes how SkillsMaster materializes a managed skill
/// into an Agent's own skills directory.
enum AgentInstallMode: String, CaseIterable, Identifiable, Codable {
    case symlink
    case copy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .symlink: AppLocalization.string("Symbolic Link")
        case .copy: AppLocalization.string("Physical Copy")
        }
    }

    var detailText: String {
        switch self {
        case .symlink:
            AppLocalization.string("Create a symbolic link in the Agent directory that points to the source-of-truth directory.")
        case .copy:
            AppLocalization.string("Copy the source-of-truth directory into the Agent directory and overwrite it again during updates.")
        }
    }
}
