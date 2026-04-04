import XCTest
@testable import SkillsMaster

@MainActor
final class SkillManagerTranslationTests: XCTestCase {
    private let dontShowPromptKey = "translationPackPromptDontShowAgain"

    private actor UnavailableTranslator: EnglishToChineseTranslating {
        func translateEnglishToChinese(_ text: String) async throws -> String {
            throw TranslationService.TranslationError.unavailable
        }
    }

    private struct StubTranslationPackAvailabilityChecker: TranslationPackAvailabilityChecking {
        let availability: TranslationPackAvailabilityChecker.Availability

        func englishToSimplifiedChinese() async -> TranslationPackAvailabilityChecker.Availability {
            availability
        }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: dontShowPromptKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: dontShowPromptKey)
        super.tearDown()
    }

    func testTranslateEnglishParagraphToChinese_preservesInstalledAvailabilityOnTransientUnavailable() async {
        let manager = SkillManager(
            translationService: UnavailableTranslator(),
            translationPackAvailabilityChecker: StubTranslationPackAvailabilityChecker(availability: .installed)
        )
        manager.translationAvailability = .installed

        do {
            _ = try await manager.translateEnglishParagraphToChinese("Hello")
            XCTFail("Expected unavailable error")
        } catch let error as TranslationService.TranslationError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Expected TranslationError.unavailable, got \(error)")
        }

        XCTAssertEqual(manager.translationAvailability, .installed)
        XCTAssertNil(manager.translationPackPrompt)
    }

    func testTranslateEnglishParagraphToChinese_promptsForMissingPackWhenAvailabilityUnknown() async {
        let manager = SkillManager(
            translationService: UnavailableTranslator(),
            translationPackAvailabilityChecker: StubTranslationPackAvailabilityChecker(availability: .supportedButNotInstalled)
        )

        do {
            _ = try await manager.translateEnglishParagraphToChinese("Hello")
            XCTFail("Expected unavailable error")
        } catch let error as TranslationService.TranslationError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Expected TranslationError.unavailable, got \(error)")
        }

        XCTAssertEqual(manager.translationAvailability, .supportedButNotInstalled)
        XCTAssertNotNil(manager.translationPackPrompt)
    }
}
