import XCTest
@testable import SkillsMaster

final class SkillDetailViewDisplayModeTests: XCTestCase {

    func testAllSkillsSelectionUsesManagementMode() {
        XCTAssertEqual(
            SkillDetailView.DisplayMode.forSidebarSelection(.allSkills),
            .management
        )
    }

    func testSkillsByAgentSelectionUsesContentOnlyMode() {
        XCTAssertEqual(
            SkillDetailView.DisplayMode.forSidebarSelection(.skillsByAgent(.claudeCode)),
            .contentOnly
        )
    }

    func testContentOnlyModeHidesManagementUI() {
        XCTAssertFalse(SkillDetailView.DisplayMode.contentOnly.showsManagementUI)
        XCTAssertTrue(SkillDetailView.DisplayMode.management.showsManagementUI)
    }

    func testManagementModeUsesInstalledTranslationScope() {
        XCTAssertEqual(
            SkillDetailView.DisplayMode.management.translationScope,
            .installed
        )
    }

    func testContentOnlyModeUsesAgentsTranslationScope() {
        XCTAssertEqual(
            SkillDetailView.DisplayMode.contentOnly.translationScope,
            .agents
        )
    }
}
