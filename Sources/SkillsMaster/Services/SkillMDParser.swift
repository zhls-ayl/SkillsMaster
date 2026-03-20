import Foundation
import Yams

/// `SkillMDParser` 负责解析 `SKILL.md` 文件。
///
/// 当前支持的格式是：`YAML frontmatter + Markdown body`。
/// 解析流程包括提取 frontmatter、用 `Yams` 解码 metadata，以及保留剩余的 Markdown 正文。
enum SkillMDParser {

    /// 解析结果：包含 metadata 与 Markdown 正文。
    struct ParseResult {
        let metadata: SkillMetadata
        let frontmatterText: String
        let markdownBody: String
    }

    /// Parse error types
    /// 解析时使用的错误类型。
    enum ParseError: Error, LocalizedError {
        case fileNotFound(URL)
        case invalidEncoding
        case noFrontmatter
        case invalidYAML(String)

        /// 面向用户展示的错误描述。
        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                "SKILL.md not found at \(url.path)"
            case .invalidEncoding:
                "File is not valid UTF-8"
            case .noFrontmatter:
                "No YAML frontmatter found (missing --- delimiters)"
            case .invalidYAML(let detail):
                "Invalid YAML frontmatter: \(detail)"
            }
        }
    }

    /// Parse SKILL.md from file URL
    /// 从文件 URL 解析 `SKILL.md`。
    ///
    /// - Parameter url: `SKILL.md` 文件路径
    /// - Returns: 解析结果
    /// - Throws: `ParseError`
    static func parse(fileURL url: URL) throws -> ParseResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound(url)
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        return try parse(content: content)
    }

    /// 仅解析 `SKILL.md` 的 frontmatter metadata。
    ///
    /// 用于 repository 列表索引场景，避免在全量扫描时保留每个 skill 的 markdown 正文。
    static func parseMetadata(fileURL url: URL) throws -> SkillMetadata {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ParseError.fileNotFound(url)
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        return try parseMetadata(content: content)
    }

    /// 从字符串内容解析 `SKILL.md`。
    /// 该方法也会在单元测试中直接使用。
    static func parse(content: String) throws -> ParseResult {
        // 提取 frontmatter 与 body。
        let (yamlString, body) = try extractFrontmatter(from: content)

        let metadata = try decodeMetadata(from: yamlString)

        return ParseResult(
            metadata: metadata,
            frontmatterText: yamlString.trimmingCharacters(in: .newlines),
            markdownBody: body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 从字符串内容中仅解析 metadata，不保留 Markdown 正文。
    static func parseMetadata(content: String) throws -> SkillMetadata {
        let (yamlString, _) = try extractFrontmatter(from: content)
        return try decodeMetadata(from: yamlString)
    }

    private static func decodeMetadata(from yamlString: String) throws -> SkillMetadata {

        // 使用 `Yams` 把 YAML 字符串解析成 `SkillMetadata`。
        let decoder = YAMLDecoder()
        do {
            return try decoder.decode(SkillMetadata.self, from: yamlString)
        } catch {
            throw ParseError.invalidYAML(error.localizedDescription)
        }
    }

    /// 从文本中提取 YAML frontmatter 与 Markdown body。
    private static func extractFrontmatter(from content: String) throws -> (String, String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // frontmatter 必须以 `---` 开头。
        guard trimmed.hasPrefix("---") else {
            throw ParseError.noFrontmatter
        }

        // Find the position of the second ---
        // Swift string indices are special, not simple Ints (due to variable Unicode character length)
        let afterFirstSeparator = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let rest = trimmed[afterFirstSeparator...]

        guard let endRange = rest.range(of: "\n---") else {
            throw ParseError.noFrontmatter
        }

        let yamlString = String(rest[rest.startIndex..<endRange.lowerBound])
        let bodyStart = rest.index(endRange.upperBound, offsetBy: 0)
        let body = String(rest[bodyStart...])

        return (yamlString, body)
    }

    /// Serialize SkillMetadata back to SKILL.md format string
    /// Used for saving after editing
    static func serialize(metadata: SkillMetadata, markdownBody: String) throws -> String {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(metadata)

        return """
        ---
        \(yamlString.trimmingCharacters(in: .whitespacesAndNewlines))
        ---

        \(markdownBody)
        """
    }
}
