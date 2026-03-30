import XCTest
@testable import SkillsMaster

@MainActor
final class RepositoryBrowserViewModelTests: XCTestCase {

    func testApplyScanResultShowsDirtyWorkingTreeNotice() async {
        let skillManager = SkillManager()
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)

        let scanResult = RepositoryManager.ScanResult(
            skills: [makeDiscoveredSkill(id: "dirty-skill")],
            cacheStatus: .bypassedDirtyWorkingTree
        )

        await vm.applyScanResult(scanResult)

        XCTAssertEqual(vm.allSkills.count, 1)
        XCTAssertEqual(
            vm.scanNoticeMessage,
            RepositoryManager.ScanCacheStatus.bypassedDirtyWorkingTree.noticeMessage
        )
    }

    func testApplyScanResultClearsDirtyWorkingTreeNoticeAfterNormalScan() async {
        let skillManager = SkillManager()
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)

        await vm.applyScanResult(.init(
            skills: [makeDiscoveredSkill(id: "dirty-skill")],
            cacheStatus: .bypassedDirtyWorkingTree
        ))
        await vm.applyScanResult(.init(
            skills: [makeDiscoveredSkill(id: "clean-skill")],
            cacheStatus: .miss
        ))

        XCTAssertEqual(vm.allSkills.map(\.id), ["clean-skill"])
        XCTAssertNil(vm.scanNoticeMessage)
    }

    func testIsInstalledReturnsTrueWhenRepositorySourceMatches() {
        let skillManager = SkillManager()
        skillManager.skills = [makeInstalledSkill(id: "repo-skill", source: "org/repo")]
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)

        XCTAssertTrue(vm.isInstalled(makeDiscoveredSkill(id: "repo-skill")))
    }

    func testIsInstalledReturnsFalseWhenRepositorySourceDiffers() {
        let skillManager = SkillManager()
        skillManager.skills = [makeInstalledSkill(id: "repo-skill", source: "other/repo")]
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)

        XCTAssertFalse(vm.isInstalled(makeDiscoveredSkill(id: "repo-skill")))
    }

    func testTargetSelectionSummaryReturnsUnselectedWhenEmpty() {
        let skillManager = SkillManager()
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)

        XCTAssertEqual(vm.targetSelectionSummary(), AppLocalization.string("No Agent Selected"))
    }

    func testDetailInstallButtonTitleReturnsMixedWhenSelectedAgentsArePartiallyInstalled() {
        let skillManager = SkillManager()
        var installedSkill = makeInstalledSkill(id: "repo-skill", source: "org/repo")
        installedSkill.installations = [makeDirectInstall(agent: .cursor, skillID: "repo-skill")]
        skillManager.skills = [installedSkill]
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)
        vm.selectedTargetAgents = [.cursor, .claudeCode]

        XCTAssertEqual(
            vm.detailInstallButtonTitle(for: makeDiscoveredSkill(id: "repo-skill")),
            AppLocalization.string("Install / Reinstall")
        )
    }

    func testSelectingInstalledSkillDefaultsToInstalledAgents() {
        let skillManager = SkillManager()
        var installedSkill = makeInstalledSkill(id: "repo-skill", source: "org/repo")
        installedSkill.installations = [makeDirectInstall(agent: .cursor, skillID: "repo-skill")]
        skillManager.skills = [installedSkill]
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)
        vm.allSkills = [makeDiscoveredSkill(id: "repo-skill")]

        vm.selectedSkillID = "repo-skill"

        XCTAssertEqual(vm.selectedTargetAgents, [.cursor])
    }

    func testManualTranslationStateIsTrackedPerSkill() {
        let skillManager = SkillManager()
        let repository = makeRepository()
        let vm = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)
        let secondVM = RepositoryBrowserViewModel(repository: repository, skillManager: skillManager)

        vm.toggleManualTranslation(for: "repo-skill-a")

        XCTAssertTrue(vm.isShowingManualTranslation(for: "repo-skill-a"))
        XCTAssertTrue(secondVM.isShowingManualTranslation(for: "repo-skill-a"))
        XCTAssertFalse(vm.isShowingManualTranslation(for: "repo-skill-b"))
    }

    func testManualTranslationStateDoesNotLeakAcrossRepositories() {
        let skillManager = SkillManager()
        let firstRepository = makeRepository()
        let secondRepository = SkillRepository(
            id: UUID(),
            name: "another-team-skills",
            repoURL: "https://github.com/org/another-repo.git",
            authType: .httpsPublic,
            platform: .github,
            isEnabled: true,
            lastSyncedAt: nil,
            localSlug: "org-another-repo",
            httpUsername: nil,
            credentialKey: nil,
            scanHiddenPaths: false,
            syncOnLaunch: false
        )
        let firstVM = RepositoryBrowserViewModel(repository: firstRepository, skillManager: skillManager)
        let secondVM = RepositoryBrowserViewModel(repository: secondRepository, skillManager: skillManager)

        firstVM.toggleManualTranslation(for: "shared-skill")

        XCTAssertTrue(firstVM.isShowingManualTranslation(for: "shared-skill"))
        XCTAssertFalse(secondVM.isShowingManualTranslation(for: "shared-skill"))
    }

    private func makeRepository() -> SkillRepository {
        SkillRepository(
            id: UUID(),
            name: "team-skills",
            repoURL: "https://github.com/org/repo.git",
            authType: .httpsPublic,
            platform: .github,
            isEnabled: true,
            lastSyncedAt: nil,
            localSlug: "org-repo",
            httpUsername: nil,
            credentialKey: nil,
            scanHiddenPaths: false,
            syncOnLaunch: false
        )
    }

    private func makeDiscoveredSkill(id: String) -> GitService.DiscoveredSkill {
        GitService.DiscoveredSkill(
            id: id,
            folderPath: "skills/\(id)",
            skillMDPath: "skills/\(id)/SKILL.md",
            metadata: SkillMetadata(name: id, description: ""),
            markdownBody: ""
        )
    }

    private func makeInstalledSkill(id: String, source: String? = nil) -> Skill {
        let lockEntry: LockEntry? = source.map { src in
            LockEntry(
                source: src,
                sourceType: "custom",
                sourceUrl: "https://github.com/\(src).git",
                skillPath: "skills/\(id)/SKILL.md",
                skillFolderHash: "abc123",
                installedAt: "2026-03-24T00:00:00.000Z",
                updatedAt: "2026-03-24T00:00:00.000Z"
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
}
