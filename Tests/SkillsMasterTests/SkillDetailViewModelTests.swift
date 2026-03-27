import XCTest
@testable import SkillsMaster

@MainActor
final class SkillDetailViewModelTests: XCTestCase {

    func testToggleManualTranslation_turnsTranslationOn() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )

        XCTAssertFalse(viewModel.isShowingManualTranslation)

        viewModel.toggleManualTranslation()

        XCTAssertTrue(viewModel.isShowingManualTranslation)
    }

    func testToggleManualTranslation_secondTapRestoresOriginalContent() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )
        viewModel.toggleManualTranslation()

        viewModel.toggleManualTranslation()

        XCTAssertFalse(viewModel.isShowingManualTranslation)
    }
}
