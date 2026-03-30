import XCTest
@testable import SkillsMaster

@MainActor
final class ClawHubBrowserViewModelTests: XCTestCase {

    actor MockClawHubService: ClawHubServiceProtocol {
        private let totalBrowseCount: Int
        private let totalSearchCount: Int
        private(set) var browseCallsLog: [(cursor: String?, limit: Int)] = []
        private(set) var searchLimitCalls: [Int] = []

        init(totalBrowseCount: Int = 0, totalSearchCount: Int = 0) {
            self.totalBrowseCount = totalBrowseCount
            self.totalSearchCount = totalSearchCount
        }

        func fetchSkills(options: ClawHubService.BrowseOptions) async throws -> ClawHubService.BrowsePage {
            browseCallsLog.append((cursor: options.cursor, limit: options.limit))

            let startIndex = options.cursor.flatMap { Int($0.replacingOccurrences(of: "cursor-", with: "")) } ?? 0
            let endIndex = min(startIndex + options.limit, totalBrowseCount)
            let items = (startIndex..<endIndex).map { makeSkill(slug: "skill-\($0)") }
            let nextCursor = endIndex < totalBrowseCount ? "cursor-\(endIndex)" : nil

            return ClawHubService.BrowsePage(
                items: items,
                nextCursor: nextCursor,
                hasMore: nextCursor != nil
            )
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
            browseCallsLog.map { $0.limit }
        }

        func browseCursors() -> [String?] {
            browseCallsLog.map { $0.cursor }
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

    private func makeDirectInstall(agent: AgentType, skillID: String) -> SkillInstallation {
        SkillInstallation(
            agentType: agent,
            path: agent.skillsDirectoryURL.appendingPathComponent(skillID),
            isSymlink: true
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

    func testCanReinstallReturnsTrueForClawHubManagedInstall() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: "browser-use")]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertTrue(viewModel.canReinstall(makeClawHubSkill(slug: "browser-use")))
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

    func testCanReinstallReturnsFalseForManualInstallWithoutClawHubLock() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: nil)]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertFalse(viewModel.canReinstall(makeClawHubSkill(slug: "browser-use")))
    }

    func testInstallButtonTitleReturnsReinstallForClawHubManagedInstall() {
        let skillManager = SkillManager()
        skillManager.skills = [makeSkill(id: "browser-use", source: "browser-use")]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()
        let skill = makeClawHubSkill(slug: "browser-use")

        XCTAssertEqual(viewModel.installButtonTitle(for: skill), MarketplaceInstallAction.reinstall.title)
        XCTAssertEqual(viewModel.detailInstallButtonTitle(for: skill), MarketplaceInstallAction.reinstall.title)
    }

    func testInstallButtonTitleReturnsInstallForNewSkill() {
        let skillManager = SkillManager()
        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        let skill = makeClawHubSkill(slug: "browser-use")

        XCTAssertEqual(viewModel.installButtonTitle(for: skill), MarketplaceInstallAction.install.title)
        XCTAssertEqual(viewModel.detailInstallButtonTitle(for: skill), MarketplaceInstallAction.install.title)
    }

    func testTargetSelectionSummaryReturnsUnselectedWhenEmpty() {
        let skillManager = SkillManager()
        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)

        XCTAssertEqual(viewModel.targetSelectionSummary(), AppLocalization.string("No Agent Selected"))
    }

    func testDetailInstallButtonTitleReturnsMixedWhenSelectedAgentsArePartiallyInstalled() {
        let skillManager = SkillManager()
        var installedSkill = makeSkill(id: "browser-use", source: "browser-use")
        installedSkill.installations = [makeDirectInstall(agent: .cursor, skillID: "browser-use")]
        skillManager.skills = [installedSkill]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()
        viewModel.selectedTargetAgents = [.cursor, .claudeCode]

        XCTAssertEqual(
            viewModel.detailInstallButtonTitle(for: makeClawHubSkill(slug: "browser-use")),
            MarketplaceInstallAction.mixed.title
        )
    }

    func testSelectingInstalledSkillDefaultsToInstalledAgents() {
        let skillManager = SkillManager()
        var installedSkill = makeSkill(id: "browser-use", source: "browser-use")
        installedSkill.installations = [makeDirectInstall(agent: .cursor, skillID: "browser-use")]
        skillManager.skills = [installedSkill]

        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()
        viewModel.displayedSkills = [makeClawHubSkill(slug: "browser-use")]

        viewModel.selectedSkillID = "browser-use"

        XCTAssertEqual(viewModel.selectedTargetAgents, [.cursor])
    }

    func testManualTranslationStateIsTrackedPerClawHubSkill() {
        let skillManager = SkillManager()
        let viewModel = ClawHubBrowserViewModel(skillManager: skillManager)
        let secondViewModel = ClawHubBrowserViewModel(skillManager: skillManager)

        viewModel.toggleManualTranslation(for: "browser-use")

        XCTAssertTrue(viewModel.isShowingManualTranslation(for: "browser-use"))
        XCTAssertTrue(secondViewModel.isShowingManualTranslation(for: "browser-use"))
        XCTAssertFalse(viewModel.isShowingManualTranslation(for: "another-skill"))
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
        XCTAssertEqual(browseCalls, [50, 50])
        let browseCursors = await service.browseCursors()
        XCTAssertEqual(browseCursors, [nil, "cursor-50"])
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
        XCTAssertEqual(browseCalls, [50, 50])

        guard let secondLastID = viewModel.displayedSkills.last?.id else {
            XCTFail("Expected list to keep loaded skills")
            return
        }

        await viewModel.loadMoreIfNeeded(after: secondLastID)
        browseCalls = await service.browseCalls()
        XCTAssertEqual(browseCalls, [50, 50], "Should not request another page when hasMoreResults is false")
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
