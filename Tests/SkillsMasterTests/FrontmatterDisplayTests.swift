import XCTest
@testable import SkillsMaster

final class FrontmatterDisplayTests: XCTestCase {

    func testExtractDescriptionPreservesSourceLineBreaksForFoldedBlockDisplay() {
        let frontmatter = """
        name: web-content-fetcher
        description: >
          Extract article content from any URL as clean Markdown.
          Uses Scrapling script as primary method.
          Falls back to Jina Reader for simple pages.
        """

        XCTAssertEqual(
            FrontmatterDisplay.value(for: "description", in: frontmatter),
            """
            Extract article content from any URL as clean Markdown.
            Uses Scrapling script as primary method.
            Falls back to Jina Reader for simple pages.
            """
        )
    }

    func testExtraFieldsExcludeCommonDisplayedFieldsButKeepUsefulMetadata() {
        let frontmatter = """
        name: obsidian
        description: Work with Obsidian vaults.
        homepage: https://help.obsidian.md
        metadata: {"clawdbot":{"emoji":"💎","requires":{"bins":["obsidian-cli"]}}}
        license: MIT
        """

        let fields = FrontmatterDisplay.extraFields(
            from: frontmatter,
            excluding: ["name", "description", "license"]
        )

        XCTAssertEqual(fields.map(\.key), ["homepage", "metadata"])
    }

    func testExtraFieldsHideMetadataWhenOnlyAuthorAndVersion() {
        let frontmatter = """
        name: sample
        description: Sample
        metadata:
          author: andy
          version: "1.0"
        """

        let fields = FrontmatterDisplay.extraFields(
            from: frontmatter,
            excluding: ["name", "description", "license"]
        )

        XCTAssertTrue(fields.isEmpty)
    }
}
