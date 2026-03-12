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
            sort: .stars,
            direction: .ascending,
            highlightedOnly: true,
            nonSuspiciousOnly: true,
            limit: 25
        )

        XCTAssertEqual(
            options.queryItems,
            [
                URLQueryItem(name: "limit", value: "25"),
                URLQueryItem(name: "sort", value: "stars"),
                URLQueryItem(name: "dir", value: "asc"),
                URLQueryItem(name: "highlighted", value: "true"),
                URLQueryItem(name: "nonSuspicious", value: "true")
            ]
        )
    }

    func testBrowseOptionsOmitSortParametersForDefaultOrdering() {
        let options = ClawHubService.BrowseOptions()
        let names = options.queryItems.map(\.name)

        XCTAssertEqual(options.queryItems.first, URLQueryItem(name: "limit", value: "50"))
        XCTAssertFalse(names.contains("sort"))
        XCTAssertFalse(names.contains("dir"))
    }
}
