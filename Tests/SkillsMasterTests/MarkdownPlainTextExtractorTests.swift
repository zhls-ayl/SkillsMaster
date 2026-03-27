import XCTest
import Markdown
@testable import SkillsMaster

final class MarkdownPlainTextExtractorTests: XCTestCase {

    func testExtractParagraphPlainText_withInlineFormatting() {
        let doc = Document(parsing: "Hello **world** and *Swift* and `code`. Visit [GitHub](https://github.com).")
        let children = Array(doc.children)
        XCTAssertEqual(children.count, 1)

        guard let paragraph = children.first as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        let plain = MarkdownPlainTextExtractor.extract(from: paragraph)
        XCTAssertEqual(plain, "Hello world and Swift and code. Visit GitHub.")
    }

    func testExtractParagraphPlainText_preservesLineBreaksAsSpaces() {
        let doc = Document(parsing: "Line1\nLine2")
        let children = Array(doc.children)
        XCTAssertEqual(children.count, 1)

        guard let paragraph = children.first as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        let plain = MarkdownPlainTextExtractor.extract(from: paragraph)
        XCTAssertEqual(plain, "Line1 Line2")
    }
}
