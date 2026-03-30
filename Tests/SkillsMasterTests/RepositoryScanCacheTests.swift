import XCTest
@testable import SkillsMaster

final class RepositoryScanCacheTests: XCTestCase {

    func testRepositoryScanCacheReturnsMatchingHeadCommitOnly() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-repo-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let cache = RepositoryScanCache(filePath: fileURL)
        let repo = SkillRepository(
            id: UUID(),
            name: "team-skills",
            repoURL: "https://example.com/org/repo.git",
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

        let skills = [
            GitService.DiscoveredSkill(
                id: "cached-skill",
                folderPath: "skills/cached-skill",
                skillMDPath: "skills/cached-skill/SKILL.md",
                metadata: SkillMetadata(name: "cached-skill", description: "cached"),
                markdownBody: "should not persist"
            )
        ]

        try await cache.saveSkills(skills, for: repo, headCommit: "abc123")

        let matched = await cache.getSkills(for: repo, headCommit: "abc123")
        let cachedSkill = try XCTUnwrap(matched?.first)
        XCTAssertEqual(cachedSkill.id, "cached-skill")
        XCTAssertEqual(cachedSkill.markdownBody, "")

        let missed = await cache.getSkills(for: repo, headCommit: "def456")
        XCTAssertNil(missed)
    }
}
