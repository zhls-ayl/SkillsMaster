import XCTest
@testable import SkillsMaster

@MainActor
final class TextFileEditorViewModelTests: XCTestCase {

    func testUnknownExtensionFallsBackToPlainTextKind() {
        let viewModel = TextFileEditorViewModel(fileURL: URL(fileURLWithPath: "/tmp/setup.sh"))

        XCTAssertEqual(viewModel.fileKind, .plainText)
    }

    func testKnownExtensionKeepsStructuredKind() {
        let viewModel = TextFileEditorViewModel(fileURL: URL(fileURLWithPath: "/tmp/config.toml"))

        XCTAssertEqual(viewModel.fileKind, .toml)
    }
}
