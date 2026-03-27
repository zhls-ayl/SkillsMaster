import XCTest
@testable import SkillsMaster

final class TranslationPackPromptPolicyTests: XCTestCase {

    func testShouldShowPrompt_firstEntry_translationEnabled_notDismissed_returnsTrue() {
        let result = TranslationPackPromptPolicy.shouldShowPrompt(
            translationEnabledOnThisScreen: true,
            dontShowAgain: false,
            hasShownThisLaunch: false
        )
        XCTAssertTrue(result)
    }

    func testShouldShowPrompt_translationDisabled_returnsFalse() {
        let result = TranslationPackPromptPolicy.shouldShowPrompt(
            translationEnabledOnThisScreen: false,
            dontShowAgain: false,
            hasShownThisLaunch: false
        )
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_dontShowAgain_returnsFalse() {
        let result = TranslationPackPromptPolicy.shouldShowPrompt(
            translationEnabledOnThisScreen: true,
            dontShowAgain: true,
            hasShownThisLaunch: false
        )
        XCTAssertFalse(result)
    }

    func testShouldShowPrompt_alreadyShownThisLaunch_returnsFalse() {
        let result = TranslationPackPromptPolicy.shouldShowPrompt(
            translationEnabledOnThisScreen: true,
            dontShowAgain: false,
            hasShownThisLaunch: true
        )
        XCTAssertFalse(result)
    }
}
