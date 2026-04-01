import XCTest
@testable import SkillsMaster

final class MigrationManagerTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-Migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
    }

    func testMigrateIfNeededCopiesLegacyLockFileToPrivateLocation() throws {
        let paths = makePaths()
        let legacyLock = paths.oldLockFilePath
        let privateLock = paths.newLockFilePath

        try writeLockFile(
            to: legacyLock,
            skills: ["agent-notifier": makeEntry(name: "agent-notifier", source: "legacy/source")]
        )

        MigrationManager.migrateIfNeeded(paths: paths)

        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateLock.path))

        let data = try Data(contentsOf: privateLock)
        let lockFile = try JSONDecoder().decode(LockFile.self, from: data)
        XCTAssertEqual(lockFile.skills["agent-notifier"]?.source, "legacy/source")
    }

    func testMigrateIfNeededDoesNotOverwriteExistingPrivateLockFile() throws {
        let paths = makePaths()

        try writeLockFile(
            to: paths.oldLockFilePath,
            skills: ["agent-notifier": makeEntry(name: "agent-notifier", source: "legacy/source")]
        )
        try writeLockFile(
            to: paths.newLockFilePath,
            skills: ["agent-notifier": makeEntry(name: "agent-notifier", source: "private/source")]
        )

        MigrationManager.migrateIfNeeded(paths: paths)

        let data = try Data(contentsOf: paths.newLockFilePath)
        let lockFile = try JSONDecoder().decode(LockFile.self, from: data)
        XCTAssertEqual(lockFile.skills["agent-notifier"]?.source, "private/source")
    }

    private func makePaths() -> MigrationManager.Paths {
        MigrationManager.Paths(
            oldSkillsDir: tempRoot.appendingPathComponent(".agents/skills"),
            oldCachePath: tempRoot.appendingPathComponent(".agents/.skillsmaster-cache.json"),
            oldReposConfigPath: tempRoot.appendingPathComponent(".agents/.skillsmaster-repos.json"),
            oldReposDir: tempRoot.appendingPathComponent(".agents/repos"),
            oldLockFilePath: tempRoot.appendingPathComponent(".agents/.skill-lock.json"),
            newSkillsDir: tempRoot.appendingPathComponent(".skillsmaster/skills"),
            newBaseDir: tempRoot.appendingPathComponent(".skillsmaster"),
            newCachePath: tempRoot.appendingPathComponent(".skillsmaster/.skillsmaster-cache.json"),
            newReposConfigPath: tempRoot.appendingPathComponent(".skillsmaster/.skillsmaster-repos.json"),
            newReposDir: tempRoot.appendingPathComponent(".skillsmaster/repos"),
            newLockFilePath: tempRoot.appendingPathComponent(".skillsmaster/.skill-lock.json")
        )
    }

    private func writeLockFile(to url: URL, skills: [String: LockEntry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockFile = LockFile(version: 3, skills: skills, dismissed: [:], lastSelectedAgents: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(lockFile).write(to: url)
    }

    private func makeEntry(name: String, source: String) -> LockEntry {
        LockEntry(
            source: source,
            sourceType: "github",
            sourceUrl: "https://github.com/\(source).git",
            skillPath: "skills/\(name)/SKILL.md",
            skillFolderHash: "hash-\(name)",
            installedAt: "2026-04-01T00:00:00Z",
            updatedAt: "2026-04-01T00:00:00Z"
        )
    }
}
