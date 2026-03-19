import XCTest
@testable import SkillsMaster

@MainActor
final class ClawHubServiceModelTests: XCTestCase {

    func testClawHubSkillFormatsBrowserURLAndCounts() {
        let skill = ClawHubSkill(
            slug: "browser-use",
            displayName: "Browser Use",
            summary: "Automation skill",
            latestVersion: "1.0.2",
            downloads: 21466,
            stars: 50,
            versionCount: 3,
            ownerHandle: "skills",
            ownerDisplayName: nil,
            updatedAtMilliseconds: 1773025618143
        )

        XCTAssertEqual(skill.browserURL.absoluteString, "https://clawhub.ai/skills/browser-use")
        XCTAssertEqual(skill.formattedDownloads, "21,466")
        XCTAssertEqual(skill.formattedStars, "50")
        XCTAssertEqual(skill.name, "Browser Use")
        XCTAssertNotNil(skill.formattedUpdatedDate)
    }

    func testClawHubSkillUsesOwnerHandleForBrowserURLWhenAvailable() {
        let skill = ClawHubSkill(
            slug: "browser-use",
            displayName: "Browser Use",
            summary: "Automation skill",
            latestVersion: "1.0.2",
            downloads: 21466,
            stars: 50,
            versionCount: 3,
            ownerHandle: "ansengu11",
            ownerDisplayName: nil,
            updatedAtMilliseconds: 1773025618143
        )

        XCTAssertEqual(skill.browserURL.absoluteString, "https://clawhub.ai/ansengu11/browser-use")
    }

    func testClawHubSkillDetailPrefersDetailVersion() {
        let skill = ClawHubSkill(
            slug: "browser-use",
            displayName: "Browser Use",
            summary: "Automation skill",
            latestVersion: nil,
            downloads: 0,
            stars: 0,
            versionCount: nil,
            ownerHandle: nil,
            ownerDisplayName: nil,
            updatedAtMilliseconds: nil
        )

        let detail = ClawHubSkillDetail(
            skill: skill,
            latestVersion: "1.0.2",
            latestVersionCreatedAt: 1771476812023,
            latestChangelog: "Updated docs",
            license: nil,
            moderationVerdict: nil,
            moderationSummary: nil
        )

        XCTAssertEqual(detail.installVersion, "1.0.2")
        XCTAssertNotNil(detail.formattedLatestVersionDate)
    }

    func testBrowseOptionsBuildExpectedQueryItems() {
        let options = ClawHubService.BrowseOptions(
            sort: .installs,
            direction: .ascending,
            highlightedOnly: true,
            nonSuspiciousOnly: true,
            limit: 25,
            cursor: "cursor-1"
        )

        XCTAssertEqual(
            options.requestBody,
            .init(
                cursor: "cursor-1",
                numItems: 25,
                sort: "installs",
                dir: "asc",
                highlightedOnly: true,
                nonSuspiciousOnly: true
            )
        )
    }

    func testNameSortDefaultsToAscendingDirection() {
        XCTAssertEqual(ClawHubService.SkillSort.name.defaultDirection, .ascending)
        XCTAssertEqual(ClawHubService.SkillSort.downloads.defaultDirection, .descending)
    }
}
