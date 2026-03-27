import Foundation
import Markdown

enum MarkdownPlainTextExtractor {

    static func extract(from markup: any Markup) -> String {
        var buffer = ""
        appendText(from: markup, into: &buffer)

        return buffer
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendText(from markup: any Markup, into buffer: inout String) {
        switch markup {
        case let text as Markdown.Text:
            buffer.append(text.string)

        case let code as InlineCode:
            buffer.append(code.code)

        case is SoftBreak:
            buffer.append(" ")

        case is LineBreak:
            buffer.append(" ")

        default:
            for child in markup.children {
                appendText(from: child, into: &buffer)
            }
        }
    }
}
