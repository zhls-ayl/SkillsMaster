import XCTest
@testable import SkillsMaster

final class LegacyRootSkillArtifactCleanerTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-LegacyCleaner-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testCleanupRemovesBrokenLegacyArtifacts() async throws {
        let staleSkill = "SkillsMaster-\(UUID().uuidString)"
        let validSkill = "frontend-design"

        let lockFilePath = tempRoot.appendingPathComponent(".agents/.skill-lock.json")
        let cacheFilePath = tempRoot.appendingPathComponent(".skillsmaster/.skillsmaster-cache.json")
        let sharedSkillsURL = tempRoot.appendingPathComponent(".skillsmaster/skills")
        let legacySkillsURL = tempRoot.appendingPathComponent(".agents/skills")
        let codexSkillsURL = tempRoot.appendingPathComponent(".codex/skills")
        let openCodeSkillsURL = tempRoot.appendingPathComponent(".config/opencode/skills")

        try createDirectory(sharedSkillsURL)
        try createDirectory(codexSkillsURL)
        try createDirectory(openCodeSkillsURL)

        let validSkillURL = sharedSkillsURL.appendingPathComponent(validSkill)
        try createSkillDirectory(at: validSkillURL, name: validSkill)

        let missingTargetURL = sharedSkillsURL.appendingPathComponent(staleSkill)
        try FileManager.default.createSymbolicLink(
            at: codexSkillsURL.appendingPathComponent(staleSkill),
            withDestinationURL: missingTargetURL
        )
        try FileManager.default.createSymbolicLink(
            at: openCodeSkillsURL.appendingPathComponent(staleSkill),
            withDestinationURL: missingTargetURL
        )

        try writeLockFile(
            to: lockFilePath,
            skills: [
                staleSkill: makeRootLevelEntry(source: "shirenchuang/web-content-fetcher"),
                validSkill: LockEntry(
                    source: "anthropics/skills",
                    sourceType: "github",
                    sourceUrl: "https://github.com/anthropics/skills.git",
                    skillPath: "skills/frontend-design/SKILL.md",
                    skillFolderHash: "good-hash",
                    installedAt: "2026-03-19T16:46:27Z",
                    updatedAt: "2026-03-19T16:46:27Z"
                ),
            ]
        )

        let cache = CommitHashCache(filePath: cacheFilePath)
        await cache.setHash(for: staleSkill, hash: "stale-hash")
        await cache.setHash(for: validSkill, hash: "valid-hash")
        await cache.setLinkedInfo(
            for: staleSkill,
            info: CommitHashCache.LinkedSkillInfo(
                source: "shirenchuang/web-content-fetcher",
                sourceType: "github",
                sourceUrl: "https://github.com/shirenchuang/web-content-fetcher.git",
                skillPath: "SKILL.md",
                skillFolderHash: "stale-folder-hash",
                linkedAt: "2026-03-20T03:23:33Z"
            )
        )
        try await cache.save()

        let cleaner = LegacyRootSkillArtifactCleaner(
            lockFilePath: lockFilePath,
            cacheFilePath: cacheFilePath,
            sharedSkillsURL: sharedSkillsURL,
            legacySkillsURL: legacySkillsURL,
            agentSkillDirectories: [codexSkillsURL, openCodeSkillsURL]
        )

        let result = try await cleaner.cleanup()

        XCTAssertEqual(result.removedSkillNames, [staleSkill])
        XCTAssertFalse(SymlinkManager.isSymlink(at: codexSkillsURL.appendingPathComponent(staleSkill)))
        XCTAssertFalse(SymlinkManager.isSymlink(at: openCodeSkillsURL.appendingPathComponent(staleSkill)))

        let lockFile = try await LockFileManager(filePath: lockFilePath).read()
        XCTAssertNil(lockFile.skills[staleSkill])
        XCTAssertNotNil(lockFile.skills[validSkill])

        let cacheReader = CommitHashCache(filePath: cacheFilePath)
        let staleHash = await cacheReader.getHash(for: staleSkill)
        let staleLinkedInfo = await cacheReader.getLinkedInfo(for: staleSkill)
        let validHash = await cacheReader.getHash(for: validSkill)
        XCTAssertNil(staleHash)
        XCTAssertNil(staleLinkedInfo)
        XCTAssertEqual(validHash, "valid-hash")
    }

    func testCleanupSkipsExistingMaterializedSkill() async throws {
        let staleSkill = "SkillsMaster-\(UUID().uuidString)"

        let lockFilePath = tempRoot.appendingPathComponent(".agents/.skill-lock.json")
        let cacheFilePath = tempRoot.appendingPathComponent(".skillsmaster/.skillsmaster-cache.json")
        let sharedSkillsURL = tempRoot.appendingPathComponent(".skillsmaster/skills")
        let legacySkillsURL = tempRoot.appendingPathComponent(".agents/skills")
        let codexSkillsURL = tempRoot.appendingPathComponent(".codex/skills")

        try createDirectory(sharedSkillsURL)
        try createDirectory(codexSkillsURL)

        let sharedSkillURL = sharedSkillsURL.appendingPathComponent(staleSkill)
        try createSkillDirectory(at: sharedSkillURL, name: "web-content-fetcher")
        try FileManager.default.createSymbolicLink(
            at: codexSkillsURL.appendingPathComponent(staleSkill),
            withDestinationURL: sharedSkillURL
        )

        try writeLockFile(
            to: lockFilePath,
            skills: [staleSkill: makeRootLevelEntry(source: "shirenchuang/web-content-fetcher")]
        )

        let cache = CommitHashCache(filePath: cacheFilePath)
        await cache.setHash(for: staleSkill, hash: "stale-hash")
        try await cache.save()

        let cleaner = LegacyRootSkillArtifactCleaner(
            lockFilePath: lockFilePath,
            cacheFilePath: cacheFilePath,
            sharedSkillsURL: sharedSkillsURL,
            legacySkillsURL: legacySkillsURL,
            agentSkillDirectories: [codexSkillsURL]
        )

        let result = try await cleaner.cleanup()

        XCTAssertTrue(result.removedSkillNames.isEmpty)
        XCTAssertTrue(SymlinkManager.isSymlink(at: codexSkillsURL.appendingPathComponent(staleSkill)))

        let lockFile = try await LockFileManager(filePath: lockFilePath).read()
        let cacheReader = CommitHashCache(filePath: cacheFilePath)
        let staleHash = await cacheReader.getHash(for: staleSkill)
        XCTAssertNotNil(lockFile.skills[staleSkill])
        XCTAssertEqual(staleHash, "stale-hash")
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func createSkillDirectory(at url: URL, name: String) throws {
        try createDirectory(url)
        try """
        ---
        name: \(name)
        description: test
        ---
        # Test Skill
        """.write(
            to: url.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeLockFile(to url: URL, skills: [String: LockEntry]) throws {
        try createDirectory(url.deletingLastPathComponent())
        let lockFile = LockFile(
            version: 3,
            skills: skills,
            dismissed: ["findSkillsPrompt": true],
            lastSelectedAgents: ["codex", "opencode"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(lockFile)
        try data.write(to: url)
    }

    private func makeRootLevelEntry(source: String) -> LockEntry {
        LockEntry(
            source: source,
            sourceType: "github",
            sourceUrl: "https://github.com/\(source).git",
            skillPath: "SKILL.md",
            skillFolderHash: "root-level-hash",
            installedAt: "2026-03-20T03:23:33Z",
            updatedAt: "2026-03-20T03:23:33Z"
        )
    }
}
