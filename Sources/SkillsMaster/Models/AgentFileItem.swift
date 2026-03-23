import Foundation

struct AgentFileItem: Identifiable, Hashable {
    let url: URL
    let relativePath: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let isTextFile: Bool
    let isProtected: Bool
    let protectionReason: String?
    let fileSize: Int?
    let modifiedDate: Date?
    var children: [AgentFileItem]?

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var childCount: Int { children?.count ?? 0 }

    var iconName: String {
        if isProtected {
            return isDirectory ? "lock.folder" : "lock.doc"
        }
        if isSymbolicLink {
            return isDirectory ? "folder.badge.questionmark" : "link"
        }
        if isDirectory {
            return "folder"
        }
        return isTextFile ? "doc.text" : "doc"
    }
}

struct AgentFileTreeSnapshot {
    let entries: [AgentFileItem]
    let watchedDirectories: [URL]
    let rootExists: Bool
}
