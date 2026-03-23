import Foundation

enum TextFilePreviewStyle: Equatable, Sendable {
    case markdown
    case code(language: String?)
}

struct TextFilePreviewContent: Equatable, Sendable {
    let text: String
    let style: TextFilePreviewStyle
    let notice: String?
}

enum TextFilePreviewFormatter {
    static let richRenderingByteLimit = 10 * 1024 * 1024
    static let richRenderingFallbackNotice = "文件超过 10 MB，已回退为原始文本预览。"

    static func makePreview(
        text: String,
        kind: TextEditableFileKind,
        fileSize: Int?
    ) -> TextFilePreviewContent {
        if let fileSize, fileSize > richRenderingByteLimit {
            return TextFilePreviewContent(
                text: text,
                style: .code(language: kind.codeLanguage),
                notice: richRenderingFallbackNotice
            )
        }

        if kind.usesMarkdownPreview {
            return TextFilePreviewContent(
                text: text,
                style: .markdown,
                notice: nil
            )
        }

        let displayText: String
        if kind.shouldPrettyPrintAsStructuredText,
           let formattedJSON = prettyPrintedJSON(text) {
            displayText = formattedJSON
        } else {
            displayText = text
        }

        return TextFilePreviewContent(
            text: displayText,
            style: .code(language: kind.codeLanguage),
            notice: nil
        )
    }

    private static func prettyPrintedJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let prettyText = String(data: prettyData, encoding: .utf8) else {
            return nil
        }

        return prettyText
    }
}
