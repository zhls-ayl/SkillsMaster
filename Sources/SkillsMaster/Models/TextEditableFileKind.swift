import Foundation

enum TextEditableFileKind: Identifiable {
    case markdown
    case json
    case toml

    var id: String { displayName }

    var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .toml: "TOML"
        }
    }

    static func from(url: URL) -> TextEditableFileKind? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "json":
            return .json
        case "toml":
            return .toml
        default:
            return nil
        }
    }
}
