import XCTest
@testable import SkillsMaster

@MainActor
final class SkillsHubServiceModelTests: XCTestCase {

    func testSkillsHubSkillPrefersLocalizedSummaryAndParsesOrigin() {
        let skill = SkillsHubSkill(
            slug: "browser-use",
            displayName: "Browser Use",
            summary: "Automation skill",
            localizedSummary: "自动化技能",
            category: .developerTools,
            downloads: 21466,
            installs: 1260,
            stars: 50,
            score: 99.6,
            latestVersion: "1.0.2",
            homepageURLString: "https://clawhub.ai/skills/browser-use",
            ownerName: "skills",
            updatedAtMilliseconds: 1773025618143,
            tags: ["automation", "browser"]
        )

        XCTAssertEqual(skill.descriptionText, "自动化技能")
        XCTAssertEqual(skill.formattedDownloads, "21,466")
        XCTAssertEqual(skill.formattedInstalls, "1,260")
        XCTAssertEqual(skill.formattedStars, "50")
        XCTAssertEqual(skill.originSourceType, "clawhub")
        XCTAssertEqual(skill.originSource, "skills/browser-use")
        XCTAssertEqual(skill.category?.displayName, "开发工具")
        XCTAssertNotNil(skill.formattedUpdatedDate)
    }

    func testSkillsHubSkillDetailPrefersArchiveMetadataVersion() {
        let skill = SkillsHubSkill(
            slug: "tapd",
            displayName: "Tapd",
            summary: "Tapd integration",
            localizedSummary: nil,
            category: .developerTools,
            downloads: 0,
            installs: 0,
            stars: 0,
            score: nil,
            latestVersion: "0.1.2",
            homepageURLString: "https://clawhub.ai/kevindai/tapd",
            ownerName: "kevindai",
            updatedAtMilliseconds: nil,
            tags: []
        )

        let detail = SkillsHubSkillDetail(
            skill: skill,
            content: SkillMDParser.ParseResult(
                metadata: SkillMetadata(name: "Tapd", description: "Tapd integration"),
                frontmatterText: "",
                markdownBody: "content"
            ),
            archiveMetadata: SkillsHubArchiveMetadata(
                ownerID: "owner-1",
                slug: "tapd",
                version: "0.1.3",
                publishedAtMilliseconds: 1774324918280
            ),
            extractedFiles: ["SKILL.md", "_meta.json"]
        )

        XCTAssertEqual(detail.installVersion, "0.1.3")
        XCTAssertEqual(detail.originSourceType, "clawhub")
        XCTAssertNotNil(detail.formattedPublishedDate)
    }

    func testSkillsHubCategoryDisplayNames() {
        XCTAssertEqual(SkillsHubCategory.aiIntelligence.displayName, "AI 智能")
        XCTAssertEqual(SkillsHubCategory.securityCompliance.displayName, "安全合规")
        XCTAssertEqual(SkillsHubCategory.communicationCollaboration.displayName, "通讯协作")
    }
}
