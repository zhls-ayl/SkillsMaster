import XCTest
@testable import SkillsMaster

@MainActor
final class SkillDetailViewModelTests: XCTestCase {

    func testToggleManualTranslation_turnsTranslationOnForCurrentSkill() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )
        let skillID = "skill-a"

        XCTAssertFalse(viewModel.isShowingManualTranslation(for: skillID))

        viewModel.toggleManualTranslation(for: skillID)

        XCTAssertTrue(viewModel.isShowingManualTranslation(for: skillID))
    }

    func testToggleManualTranslation_secondTapRestoresOriginalContentForSameSkill() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )
        let skillID = "skill-a"
        viewModel.toggleManualTranslation(for: skillID)

        viewModel.toggleManualTranslation(for: skillID)

        XCTAssertFalse(viewModel.isShowingManualTranslation(for: skillID))
    }

    func testToggleManualTranslationDoesNotAffectOtherSkills() {
        let viewModel = SkillDetailViewModel(
            skillManager: SkillManager(),
            toolPreferences: ToolPreferencesStore()
        )

        viewModel.toggleManualTranslation(for: "skill-a")

        XCTAssertTrue(viewModel.isShowingManualTranslation(for: "skill-a"))
        XCTAssertFalse(viewModel.isShowingManualTranslation(for: "skill-b"))
    }

    func testManualTranslationStateIsSharedAcrossDetailViewModelsInSameSession() {
        let skillManager = SkillManager()
        let firstViewModel = SkillDetailViewModel(
            skillManager: skillManager,
            toolPreferences: ToolPreferencesStore()
        )
        let secondViewModel = SkillDetailViewModel(
            skillManager: skillManager,
            toolPreferences: ToolPreferencesStore()
        )

        firstViewModel.toggleManualTranslation(for: "skill-a")

        XCTAssertTrue(secondViewModel.isShowingManualTranslation(for: "skill-a"))
    }
}
