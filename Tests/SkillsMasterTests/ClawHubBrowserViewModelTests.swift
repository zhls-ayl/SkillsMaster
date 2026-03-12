import XCTest
@testable import SkillsMaster

@MainActor
final class ClawHubBrowserViewModelTests: XCTestCase {

    actor MockClawHubService: ClawHubServiceProtocol {
        private let totalBrowseCount: Int
        private let totalSearchCount: Int
        private(set) var browseLimitCalls: [Int] = []
        private(set) var searchLimitCalls: [Int] = []

        init(totalBrowseCount: Int = 0, totalSearchCount: Int = 0) {
            self.totalBrowseCount = totalBrowseCount
            self.totalSearchCount = totalSearchCount
        }

        func fetchSkills(options: ClawHubService.BrowseOptions) async throws -> [ClawHubSkill] {
            browseLimitCalls.append(options.limit)
            return makeSkills(count: min(options.limit, totalBrowseCount))
        }

        func searchSkills(query: String, limit: Int) async throws -> [ClawHubSkill] {
            searchLimitCalls.append(limit)
            return makeSkills(count: min(limit, totalSearchCount))
        }

        func fetchSkillDetail(slug: String) async throws -> ClawHubSkillDetail {
            ClawHubSkillDetail(
                skill: makeSkill(slug: slug),
                latestVersion: "1.0.0",
                latestVersionCreatedAt: nil,
                latestChangelog: nil,
                license: nil,
                moderationVerdict: nil,
                moderationSummary: nil
            )
        }

        func fetchSkillContent(slug: String) async throws -> String {
            "---\nname: \(slug)\n---\ncontent"
        }

        func downloadSkillArchive(slug: String, version: String) async throws -> Data {
            Data("archive".utf8)
        }

        func browseCalls() -> [Int] {
            browseLimitCalls
        }

        func searchCalls() -> [Int] {
            searchLimitCalls
        }

        private func makeSkills(count: Int) -> [ClawHubSkill] {
            (0..<count).map { makeSkill(slug: "skill-\($0)") }
        }

        private func makeSkill(slug: String) -> ClawHubSkill {
            ClawHubSkill(
                slug: slug,
                displayName: slug,
                summary: "",
                latestVersion: "1.0.0",
                downloads: 1,
                stars: 1,
                versionCount: 1,
                ownerHandle: nil,
                ownerDisplayName: nil,
                updatedAtMilliseconds: nil
            )
        }
    }

    private func makeSkill(id: String, source: String? = nil, sourceType: String = "clawhub") -> Skill {
        let lockEntry: LockEntry? = source.map { src in
            LockEntry(
                source: src,
                sourceType: sourceType,
                sourceUrl: "https://clawhub.ai/skills/\(src)",
                skillPath: "\(id)/SKILL.md",
                skillFolderHash: "",
                installedAt: "2025-01-01T00:00:00Z",
                updatedAt: "2025-01-01T00:00:00Z"
            )
        }

        return Skill(
            id: id,
            canonicalURL: URL(fileURLWithPath: "/tmp/skills/\(id)"),
            metadata: SkillMetadata(name: id, description: ""),
            markdownBody: "",
            scope: .shared,
            installations: [],
            lockEntry: lockEntry
        )
    }

    private func makeClawHubSkill(slug: String) -> ClawHubSkill {
        ClawHubSkill(
            slug: slug,
            displayName: slug,
            summary: "",
            latestVersion: "1.0.0",
            downloads: 10,
            stars: 2,
            versionCount: 1,
            ownerHandle: "skills",
            ownerDisplayName: nil,
            updatedAtMilliseconds: nil
        )
    }

    func testIsInstalledReturnsTrueWhenClawHubSourceMatchesSlug() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: "browser-use")]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertTrue(viewModel.isInstalled(makeClawHubSkill(slug: "browser-use")))
    }

    func testIsInstalledReturnsFalseWhenClawHubSourceDiffers() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: "other-skill")]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertFalse(viewModel.isInstalled(makeClawHubSkill(slug: "browser-use")))
    }

    func testIsInstalledFallsBackToSkillIDForManualInstall() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: nil)]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertTrue(viewModel.isInstalled(makeClawHubSkill(slug: "browser-use")))
    }

    func testLoadMoreInBrowseModeIncreasesLimit() async {
        let skillManager = SkillManager()
        let service = MockClawHubService(totalBrowseCount: 120)
        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager, service: service)

        await viewModel.onAppear()
        XCTAssertEqual(viewModel.displayedSkills.count, 50)
        XCTAssertTrue(viewModel.hasMoreResults)

        guard let lastID = viewModel.displayedSkills.last?.id else {
            XCTFail("Expected initial browse list to contain skills")
            return
        }

        await viewModel.loadMoreIfNeeded(after: lastID)

        XCTAssertEqual(viewModel.displayedSkills.count, 100)
        XCTAssertTrue(viewModel.hasMoreResults)
        let browseCalls = await service.browseCalls()
        XCTAssertEqual(browseCalls, [50, 100])
    }

    func testLoadMoreStopsWhenNoMoreData() async {
        let skillManager = SkillManager()
        let service = MockClawHubService(totalBrowseCount: 80)
        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager, service: service)

        await viewModel.onAppear()
        guard let firstLastID = viewModel.displayedSkills.last?.id else {
            XCTFail("Expected initial browse list to contain skills")
            return
        }

        await viewModel.loadMoreIfNeeded(after: firstLastID)
        XCTAssertEqual(viewModel.displayedSkills.count, 80)
        XCTAssertFalse(viewModel.hasMoreResults)
        var browseCalls = await service.browseCalls()
        XCTAssertEqual(browseCalls, [50, 100])

        guard let secondLastID = viewModel.displayedSkills.last?.id else {
            XCTFail("Expected list to keep loaded skills")
            return
        }

        await viewModel.loadMoreIfNeeded(after: secondLastID)
        browseCalls = await service.browseCalls()
        XCTAssertEqual(browseCalls, [50, 100], "Should not request another page when hasMoreResults is false")
    }

    func testLoadMoreInSearchModeUsesHigherSearchLimit() async {
        let skillManager = SkillManager()
        let service = MockClawHubService(totalSearchCount: 130)
        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager, service: service)

        viewModel.searchText = "skill"
        await viewModel.refresh()
        XCTAssertEqual(viewModel.displayedSkills.count, 50)
        XCTAssertTrue(viewModel.hasMoreResults)

        guard let lastID = viewModel.displayedSkills.last?.id else {
            XCTFail("Expected initial search list to contain skills")
            return
        }

        await viewModel.loadMoreIfNeeded(after: lastID)

        XCTAssertEqual(viewModel.displayedSkills.count, 100)
        XCTAssertTrue(viewModel.hasMoreResults)
        let searchCalls = await service.searchCalls()
        XCTAssertEqual(searchCalls, [50, 100])
    }
}
