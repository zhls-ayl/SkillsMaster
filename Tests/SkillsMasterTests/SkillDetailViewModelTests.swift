import XCTest
@testable import SkillsMaster

@MainActor
final class SkillDetailViewModelTests: XCTestCase {

    func testManualTranslationRequest_marksCurrentSkillAsTranslated() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )

        XCTAssertTrue(viewModel.canRequestManualTranslation(for: "skill-a"))
        XCTAssertFalse(viewModel.isShowingManualTranslation)

        viewModel.requestManualTranslation(for: "skill-a")

        XCTAssertTrue(viewModel.isShowingManualTranslation)
        XCTAssertFalse(viewModel.canRequestManualTranslation(for: "skill-a"))
        XCTAssertTrue(viewModel.canRequestManualTranslation(for: "skill-b"))
    }

    func testResetManualTranslation_keepsStateForSameSkill() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )
        viewModel.requestManualTranslation(for: "skill-a")

        viewModel.resetManualTranslationIfNeeded(for: "skill-a")

        XCTAssertTrue(viewModel.isShowingManualTranslation)
        XCTAssertFalse(viewModel.canRequestManualTranslation(for: "skill-a"))
    }

    func testResetManualTranslation_clearsStateWhenSwitchingSkill() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )
        viewModel.requestManualTranslation(for: "skill-a")

        viewModel.resetManualTranslationIfNeeded(for: "skill-b")

        XCTAssertFalse(viewModel.isShowingManualTranslation)
        XCTAssertTrue(viewModel.canRequestManualTranslation(for: "skill-a"))
        XCTAssertTrue(viewModel.canRequestManualTranslation(for: "skill-b"))
    }
}
