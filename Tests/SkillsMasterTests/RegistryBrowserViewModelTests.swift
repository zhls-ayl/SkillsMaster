import XCTest
@testable import SkillsMaster

/// `RegistryBrowserViewModel` 的单元测试。
///
/// 这些测试主要覆盖 source-aware 的 “Installed” 标记逻辑，
/// 用来防止不同 repository 中同名 `skillId` 被错误地同时标记为已安装。
///
/// 由于 `RegistryBrowserViewModel` 和 `SkillManager` 都是 `@MainActor` 隔离对象，
/// 因此测试类也需要运行在 `@MainActor` 上。
@MainActor
final class RegistryBrowserViewModelTests: XCTestCase {

    actor MockRegistryService: SkillRegistryServiceProtocol {
        private let leaderboardSkills: [RegistrySkill]
        private let searchTotalCount: Int
        private(set) var leaderboardCallCount = 0
        private(set) var searchLimitCalls: [Int] = []

        init(leaderboardSkills: [RegistrySkill] = [], searchTotalCount: Int = 0) {
            self.leaderboardSkills = leaderboardSkills
            self.searchTotalCount = searchTotalCount
        }

        func search(query: String, limit: Int) async throws -> [RegistrySkill] {
            searchLimitCalls.append(limit)
            let targetCount = min(limit, searchTotalCount)
            return (0..<targetCount).map { index in
                RegistrySkill(
                    id: "owner/repo/search-\(index)",
                    skillId: "search-\(index)",
                    name: "search-\(index)",
                    installs: index,
                    source: "owner/repo",
                    installsYesterday: nil,
                    change: nil
                )
            }
        }

        func fetchLeaderboard(category: SkillRegistryService.LeaderboardCategory) async throws -> [RegistrySkill] {
            leaderboardCallCount += 1
            return leaderboardSkills
        }

        func clearCache() async {}

        func leaderboardCalls() -> Int {
            leaderboardCallCount
        }

        func searchCalls() -> [Int] {
            searchLimitCalls
        }
    }

    // MARK: - Helpers

    /// 创建一个最小可用的 `Skill` model，用于测试。
    private func makeSkill(id: String, source: String? = nil) -> Skill {
        // 只有传入 `source` 时才构造 `LockEntry`；否则表示手动安装的 skill。
        let lockEntry: LockEntry? = source.map { src in
            LockEntry(
                source: src,
                sourceType: "github",
                sourceUrl: "https://github.com/\(src).git",
                skillPath: "skills/\(id)/SKILL.md",
                skillFolderHash: "abc123",
                installedAt: "2025-01-01T00:00:00Z",
                updatedAt: "2025-01-01T00:00:00Z"
            )
        }

        return Skill(
            id: id,
            canonicalURL: URL(fileURLWithPath: "/tmp/skills/\(id)"),
            metadata: SkillMetadata(name: id, description: ""),
            markdownBody: "",
            scope: .unassigned,
            installations: [],
            lockEntry: lockEntry
        )
    }

    /// 创建一个最小可用的 `RegistrySkill`，用于 registry 场景测试。
    private func makeRegistrySkill(skillId: String, source: String) -> RegistrySkill {
        RegistrySkill(
            id: "\(source)/\(skillId)",
            skillId: skillId,
            name: skillId,
            installs: 100,
            source: source,
            installsYesterday: nil,
            change: nil
        )
    }

    // MARK: - isInstalled Tests

    /// 验证：当 `skillId` 与 `source` 都匹配时，`isInstalled` 返回 `true`。
    func testIsInstalledReturnsTrueWhenSourceMatches() {
        let skillManager = SkillManager()
        // Simulate a locally installed skill with a lock entry recording its source repo
        skillManager.skills = [makeSkill(id: "ui-ux-pro-max", source: "alice/skills")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Registry skill from the SAME repo should be marked as installed
        let registrySkill = makeRegistrySkill(skillId: "ui-ux-pro-max", source: "alice/skills")
        XCTAssertTrue(vm.isInstalled(registrySkill), "Should be installed when skillId and source both match")
    }

    /// 验证：当 `skillId` 相同但 `source` 不同时，`isInstalled` 返回 `false`。
    func testIsInstalledReturnsFalseWhenSourceDiffers() {
        let skillManager = SkillManager()
        // Locally installed from "alice/skills"
        skillManager.skills = [makeSkill(id: "ui-ux-pro-max", source: "alice/skills")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Registry skill from a DIFFERENT repo should NOT be marked as installed
        let registrySkill = makeRegistrySkill(skillId: "ui-ux-pro-max", source: "bob/other-skills")
        XCTAssertFalse(vm.isInstalled(registrySkill), "Should NOT be installed when source differs even if skillId matches")
    }

    /// 验证：对于没有 `lockEntry` 的手动安装 skill，`isInstalled` 会回退到仅按 `skillId` 匹配。
    func testIsInstalledFallbackForSkillWithoutLockEntry() {
        let skillManager = SkillManager()
        // Manually installed skill — no lock entry, so no source info
        skillManager.skills = [makeSkill(id: "my-custom-skill")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Any registry skill with matching skillId should be marked as installed (fallback behavior)
        let registrySkill = makeRegistrySkill(skillId: "my-custom-skill", source: "anyone/any-repo")
        XCTAssertTrue(vm.isInstalled(registrySkill), "Should be installed via ID-only fallback when no lock entry exists")
    }

    /// 验证：对完全未安装的 skill，`isInstalled` 应返回 `false`。
    func testIsInstalledReturnsFalseForUninstalledSkill() {
        let skillManager = SkillManager()
        // Install a different skill
        skillManager.skills = [makeSkill(id: "some-other-skill", source: "alice/skills")]

        let vm = RegistryBrowserViewModel(skillManager: skillManager)
        vm.syncInstalledSkills()

        // Registry skill with a completely different skillId should not be installed
        let registrySkill = makeRegistrySkill(skillId: "ui-ux-pro-max", source: "alice/skills")
        XCTAssertFalse(vm.isInstalled(registrySkill), "Should NOT be installed when skillId doesn't match any local skill")
    }

    func testLeaderboardModeUsesLocalPaginationAfterInitialFetch() async {
        let skillManager = SkillManager()
        let leaderboardSkills = (0..<130).map { index in
            RegistrySkill(
                id: "owner/repo/\(index)",
                skillId: "skill-\(index)",
                name: "skill-\(index)",
                installs: index,
                source: "owner/repo",
                installsYesterday: nil,
                change: nil
            )
        }
        let service = MockRegistryService(leaderboardSkills: leaderboardSkills)
        let vm = RegistryBrowserViewModel(skillManager: skillManager, registryService: service)

        await vm.onAppear()
        XCTAssertEqual(vm.displayedSkills.count, 50)
        XCTAssertTrue(vm.hasMoreResults)
        var leaderboardCalls = await service.leaderboardCalls()
        XCTAssertEqual(leaderboardCalls, 1)

        guard let lastID = vm.displayedSkills.last?.id else {
            XCTFail("Expected leaderboard skills")
            return
        }

        await vm.loadMoreIfNeeded(after: lastID)
        XCTAssertEqual(vm.displayedSkills.count, 100)
        leaderboardCalls = await service.leaderboardCalls()
        XCTAssertEqual(leaderboardCalls, 1, "Leaderboard load-more should not re-fetch network data")
    }

    func testSearchModeLoadMoreRequestsHigherLimit() async {
        let skillManager = SkillManager()
        let service = MockRegistryService(searchTotalCount: 140)
        let vm = RegistryBrowserViewModel(skillManager: skillManager, registryService: service)

        vm.searchText = "skill"
        await vm.refresh()
        XCTAssertEqual(vm.displayedSkills.count, 50)
        XCTAssertTrue(vm.hasMoreResults)
        var searchCalls = await service.searchCalls()
        XCTAssertEqual(searchCalls, [50])

        guard let lastID = vm.displayedSkills.last?.id else {
            XCTFail("Expected search skills")
            return
        }

        await vm.loadMoreIfNeeded(after: lastID)
        XCTAssertEqual(vm.displayedSkills.count, 100)
        XCTAssertTrue(vm.hasMoreResults)
        searchCalls = await service.searchCalls()
        XCTAssertEqual(searchCalls, [50, 100])
    }

    func testSearchModeStopsWhenNoMoreData() async {
        let skillManager = SkillManager()
        let service = MockRegistryService(searchTotalCount: 80)
        let vm = RegistryBrowserViewModel(skillManager: skillManager, registryService: service)

        vm.searchText = "skill"
        await vm.refresh()
        guard let lastID = vm.displayedSkills.last?.id else {
            XCTFail("Expected search skills")
            return
        }

        await vm.loadMoreIfNeeded(after: lastID)
        XCTAssertEqual(vm.displayedSkills.count, 80)
        XCTAssertFalse(vm.hasMoreResults)
        var searchCalls = await service.searchCalls()
        XCTAssertEqual(searchCalls, [50, 100])

        guard let secondLastID = vm.displayedSkills.last?.id else {
            XCTFail("Expected loaded list to remain available")
            return
        }
        await vm.loadMoreIfNeeded(after: secondLastID)
        searchCalls = await service.searchCalls()
        XCTAssertEqual(searchCalls, [50, 100], "Should not continue requesting when no more results")
    }
}
