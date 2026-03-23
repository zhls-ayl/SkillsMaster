import Foundation

struct AgentFileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let isProtected: Bool
    let protectionReason: String?
    var loadedChildCount: Int?

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var isExpandable: Bool { isDirectory && !isSymbolicLink }

    var iconName: String {
        if isProtected {
            return isDirectory ? "lock.folder" : "lock.doc"
        }
        if isSymbolicLink {
            return isDirectory ? "folder.badge.questionmark" : "link"
        }
        return isDirectory ? "folder" : "doc"
    }
}

struct AgentFileDetails: Sendable {
    let fileSize: Int?
    let modifiedDate: Date?
    let isTextFile: Bool
}

struct AgentFileRootSnapshot: Sendable {
    let entries: [AgentFileItem]
    let rootExists: Bool
    let watchBaseURL: URL
}
