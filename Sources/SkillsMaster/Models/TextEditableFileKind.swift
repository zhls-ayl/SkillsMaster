import Foundation

enum TextEditableFileKind: Identifiable, Equatable, Sendable {
    case markdown
    case json
    case toml
    case yaml
    case plainText
    case log

    var id: String { displayName }

    var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .toml: "TOML"
        case .yaml: "YAML"
        case .plainText: "Text"
        case .log: "Log"
        }
    }

    var codeLanguage: String? {
        switch self {
        case .markdown: "markdown"
        case .json: "json"
        case .toml: "toml"
        case .yaml: "yaml"
        case .plainText: "text"
        case .log: "log"
        }
    }

    var usesMarkdownPreview: Bool {
        self == .markdown
    }

    var shouldPrettyPrintAsStructuredText: Bool {
        self == .json
    }

    static func from(url: URL) -> TextEditableFileKind? {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return .markdown
        case "json":
            return .json
        case "toml":
            return .toml
        case "yaml", "yml":
            return .yaml
        case "txt":
            return .plainText
        case "log":
            return .log
        default:
            return nil
        }
    }
}
