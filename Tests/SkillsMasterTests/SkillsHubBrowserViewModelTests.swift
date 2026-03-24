import XCTest
@testable import SkillsMaster

@MainActor
final class SkillsHubBrowserViewModelTests: XCTestCase {

    actor MockSkillsHubService: SkillsHubServiceProtocol {
        private let totalCount: Int
        private(set) var browseCallsLog: [(page: Int, keyword: String?, category: SkillsHubCategory?, sort: SkillsHubService.SkillSort)] = []
        private(set) var featuredRequested = false

        init(totalCount: Int = 0) {
            self.totalCount = totalCount
        }

        func clearCache() async {}

        func fetchSkills(options: SkillsHubService.BrowseOptions) async throws -> SkillsHubService.BrowsePage {
            browseCallsLog.append(
                (
                    page: options.page,
                    keyword: options.keyword,
                    category: options.category,
                    sort: options.sort
                )
            )

            let pageSize = options.pageSize
            let startIndex = max((options.page - 1) * pageSize, 0)
            let endIndex = min(startIndex + pageSize, totalCount)
            let prefix = options.category?.rawValue ?? "skill"
            let items = (startIndex..<endIndex).map { index in
                makeSkill(
                    slug: "\(prefix)-\(index)",
                    name: "\(prefix)-\(index)",
                    category: options.category
                )
            }
            return SkillsHubService.BrowsePage(items: items, total: totalCount)
        }

        func fetchFeaturedSkills() async throws -> [SkillsHubSkill] {
            featuredRequested = true
            return [
                makeSkill(slug: "skill-0", name: "skill-0", category: .developerTools),
                makeSkill(slug: "skill-1", name: "skill-1", category: .developerTools)
            ]
        }

        func searchSkills(query: String, limit: Int) async throws -> [SkillsHubSkill] {
            [makeSkill(slug: query, name: query, category: nil)]
        }

        func fetchSkill(slug: String) async throws -> SkillsHubSkill {
            makeSkill(slug: slug, name: slug, category: .developerTools)
        }

        func fetchSkillDetail(slug: String, seed: SkillsHubSkill?) async throws -> SkillsHubSkillDetail {
            let skill = seed ?? makeSkill(slug: slug, name: slug, category: .developerTools)
            return SkillsHubSkillDetail(
                skill: skill,
                content: SkillMDParser.ParseResult(
                    metadata: SkillMetadata(name: skill.name, description: skill.descriptionText),
                    frontmatterText: "",
                    markdownBody: "content"
                ),
                archiveMetadata: SkillsHubArchiveMetadata(
                    ownerID: "owner",
                    slug: slug,
                    version: "1.0.0",
                    publishedAtMilliseconds: nil
                ),
                extractedFiles: ["SKILL.md", "_meta.json"]
            )
        }

        func downloadSkillArchive(slug: String) async throws -> Data {
            Data("archive".utf8)
        }

        func browseCalls() -> [(page: Int, keyword: String?, category: SkillsHubCategory?, sort: SkillsHubService.SkillSort)] {
            browseCallsLog
        }

        func requestedFeatured() -> Bool {
            featuredRequested
        }

        private func makeSkill(slug: String, name: String, category: SkillsHubCategory?) -> SkillsHubSkill {
            SkillsHubSkill(
                slug: slug,
                displayName: name,
                summary: "",
                localizedSummary: nil,
                category: category,
                downloads: 10,
                installs: 2,
                stars: 1,
                score: 100,
                latestVersion: "1.0.0",
                homepageURLString: "https://clawhub.ai/skills/\(slug)",
                ownerName: "skills",
                updatedAtMilliseconds: nil,
                tags: []
            )
        }
    }

    private func makeInstalledSkill(id: String, source: String? = nil, sourceType: String = "skillhub") -> Skill {
        let lockEntry: LockEntry? = source.map { src in
            LockEntry(
                source: src,
                sourceType: sourceType,
                sourceUrl: "https://skillhub.tencent.com/",
                skillPath: "\(id)/SKILL.md",
                skillFolderHash: "",
                installedAt: "2026-03-24T00:00:00.000Z",
                updatedAt: "2026-03-24T00:00:00.000Z",
                sourceVersion: "1.0.0"
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

    private func makeSkillsHubSkill(slug: String) -> SkillsHubSkill {
        SkillsHubSkill(
            slug: slug,
            displayName: slug,
            summary: "",
            localizedSummary: nil,
            category: .developerTools,
            downloads: 10,
            installs: 2,
            stars: 1,
            score: 100,
            latestVersion: "1.0.0",
            homepageURLString: "https://clawhub.ai/skills/\(slug)",
            ownerName: "skills",
            updatedAtMilliseconds: nil,
            tags: []
        )
    }

    func testIsInstalledReturnsTrueWhenSkillsHubSourceMatchesSlug() {
        let skillManager = SkillManager()
        skillManager.skills = [makeInstalledSkill(id: "github", source: "github")]

        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertTrue(viewModel.isInstalled(makeSkillsHubSkill(slug: "github")))
    }

    func testCanReinstallReturnsFalseForManualInstallWithoutSkillsHubLock() {
        let skillManager = SkillManager()
        skillManager.skills = [makeInstalledSkill(id: "github", source: nil)]

        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()

        XCTAssertFalse(viewModel.canReinstall(makeSkillsHubSkill(slug: "github")))
    }

    func testTargetSelectionSummaryReturnsUnselectedWhenEmpty() {
        let skillManager = SkillManager()
        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager)

        XCTAssertEqual(viewModel.targetSelectionSummary(), "未选择 Agent")
    }

    func testDetailInstallButtonTitleReturnsMixedWhenSelectedAgentsArePartiallyInstalled() {
        let skillManager = SkillManager()
        var installedSkill = makeInstalledSkill(id: "github", source: "github")
        installedSkill.installations = [makeDirectInstall(agent: .cursor, skillID: "github")]
        skillManager.skills = [installedSkill]

        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()
        viewModel.selectedTargetAgents = [.cursor, .claudeCode]

        XCTAssertEqual(
            viewModel.detailInstallButtonTitle(for: makeSkillsHubSkill(slug: "github")),
            "Install / Reinstall"
        )
    }

    func testSelectingInstalledSkillDefaultsToInstalledAgents() {
        let skillManager = SkillManager()
        var installedSkill = makeInstalledSkill(id: "github", source: "github")
        installedSkill.installations = [makeDirectInstall(agent: .cursor, skillID: "github")]
        skillManager.skills = [installedSkill]

        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager)
        viewModel.syncInstalledSkills()
        viewModel.displayedSkills = [makeSkillsHubSkill(slug: "github")]

        viewModel.selectedSkillID = "github"

        XCTAssertEqual(viewModel.selectedTargetAgents, [.cursor])
    }

    func testOnAppearLoadsFeaturedAndFirstPage() async {
        let skillManager = SkillManager()
        let service = MockSkillsHubService(totalCount: 60)
        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager, service: service)

        await viewModel.onAppear()

        XCTAssertEqual(viewModel.displayedSkills.count, 24)
        XCTAssertEqual(viewModel.totalPages, 3)
        let browseCalls = await service.browseCalls()
        let featuredRequested = await service.requestedFeatured()
        XCTAssertEqual(browseCalls.count, 1)
        XCTAssertEqual(browseCalls.first?.page, 1)
        XCTAssertEqual(featuredRequested, true)
        XCTAssertTrue(viewModel.isFeatured(makeSkillsHubSkill(slug: "skill-0")))
    }

    func testRefreshUsesCurrentSearchKeyword() async {
        let skillManager = SkillManager()
        let service = MockSkillsHubService(totalCount: 10)
        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager, service: service)

        viewModel.searchText = "tapd"
        await viewModel.refresh()

        let browseCalls = await service.browseCalls()
        XCTAssertEqual(browseCalls.last?.keyword, "tapd")
    }

    func testSelectCategoryResetsPageAndRequestsCategory() async {
        let skillManager = SkillManager()
        let service = MockSkillsHubService(totalCount: 80)
        let viewModel = SkillsHubBrowserViewModel(skillManager: skillManager, service: service)

        await viewModel.onAppear()
        viewModel.goToNextPage()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(viewModel.currentPage, 2)

        viewModel.selectCategory(.developerTools)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(viewModel.currentPage, 1)
        let browseCalls = await service.browseCalls()
        XCTAssertEqual(browseCalls.last?.category, .developerTools)
    }
}
