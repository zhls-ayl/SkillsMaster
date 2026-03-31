import Foundation

struct SkillRelatedFileNode: Identifiable, Hashable, Sendable {
    let item: AgentFileItem
    let children: [SkillRelatedFileNode]

    var id: String { item.id }
}

struct SkillRelatedFilesSnapshot: Sendable {
    let nodes: [SkillRelatedFileNode]
    let watchPaths: [URL]
    let extraItemCount: Int
    let hasNestedDirectories: Bool
}
