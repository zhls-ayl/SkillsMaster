import XCTest
@testable import SkillsMaster

final class SkillDetailViewDisplayModeTests: XCTestCase {

    func testDashboardSelectionUsesManagementMode() {
        XCTAssertEqual(
            SkillDetailView.DisplayMode.forSidebarSelection(.dashboard),
            .management
        )
    }

    func testAgentSkillsSelectionUsesContentOnlyMode() {
        XCTAssertEqual(
            SkillDetailView.DisplayMode.forSidebarSelection(.agentSkills(.claudeCode)),
            .contentOnly
        )
    }

    func testContentOnlyModeHidesManagementUI() {
        XCTAssertFalse(SkillDetailView.DisplayMode.contentOnly.showsManagementUI)
        XCTAssertTrue(SkillDetailView.DisplayMode.management.showsManagementUI)
    }
}
