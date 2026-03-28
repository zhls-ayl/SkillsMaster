import XCTest
@testable import SkillsMaster

final class TranslationPlatformSupportTests: XCTestCase {

    func testCanCheckLanguageAvailabilityMatchesCurrentPlatformExpectation() {
        XCTAssertEqual(
            TranslationPlatformSupport.canCheckLanguageAvailability,
            expectedTranslationPlatformSupport
        )
    }

    func testCanPerformInlineTranslationMatchesCurrentPlatformExpectation() {
        XCTAssertEqual(
            TranslationPlatformSupport.canPerformInlineTranslation,
            expectedTranslationPlatformSupport
        )
    }

    private var expectedTranslationPlatformSupport: Bool {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif

        return false
    }
}
