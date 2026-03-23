import XCTest
@testable import SkillsMaster

final class TextFilePreviewFormatterTests: XCTestCase {

    func testTextEditableFileKindSupportsNewTextExtensions() {
        XCTAssertEqual(
            TextEditableFileKind.from(url: URL(fileURLWithPath: "/tmp/config.yaml")),
            .yaml
        )
        XCTAssertEqual(
            TextEditableFileKind.from(url: URL(fileURLWithPath: "/tmp/config.yml")),
            .yaml
        )
        XCTAssertEqual(
            TextEditableFileKind.from(url: URL(fileURLWithPath: "/tmp/notes.txt")),
            .plainText
        )
        XCTAssertEqual(
            TextEditableFileKind.from(url: URL(fileURLWithPath: "/tmp/app.log")),
            .log
        )
    }

    func testMarkdownUsesNativeMarkdownRenderingWithinLimit() {
        let preview = TextFilePreviewFormatter.makePreview(
            text: "# Title\n\nHello",
            kind: .markdown,
            fileSize: 128
        )

        XCTAssertEqual(preview.style, .markdown)
        XCTAssertNil(preview.notice)
        XCTAssertEqual(preview.text, "# Title\n\nHello")
    }

    func testLargeMarkdownFallsBackToRawCodePreview() {
        let preview = TextFilePreviewFormatter.makePreview(
            text: "# Title\n\nHello",
            kind: .markdown,
            fileSize: TextFilePreviewFormatter.richRenderingByteLimit + 1
        )

        XCTAssertEqual(preview.style, .code(language: "markdown"))
        XCTAssertEqual(preview.notice, TextFilePreviewFormatter.richRenderingFallbackNotice)
        XCTAssertEqual(preview.text, "# Title\n\nHello")
    }

    func testJSONIsPrettyPrintedInCodePreview() {
        let preview = TextFilePreviewFormatter.makePreview(
            text: #"{"b":1,"a":2}"#,
            kind: .json,
            fileSize: 64
        )

        XCTAssertEqual(preview.style, .code(language: "json"))
        XCTAssertNil(preview.notice)
        XCTAssertEqual(
            preview.text,
            """
            {
              "a" : 2,
              "b" : 1
            }
            """
        )
    }

    func testInvalidJSONFallsBackToOriginalText() {
        let preview = TextFilePreviewFormatter.makePreview(
            text: #"{"broken":}"#,
            kind: .json,
            fileSize: 64
        )

        XCTAssertEqual(preview.style, .code(language: "json"))
        XCTAssertEqual(preview.text, #"{"broken":}"#)
        XCTAssertNil(preview.notice)
    }
}
