import XCTest
@testable import SkillsMaster

final class LegacySkillsCLIImportServiceTests: XCTestCase {

    private var tempRoot: URL!
    private var legacyLockFilePath: URL!
    private var privateLockFilePath: URL!
    private var privateSharedSkillsURL: URL!
    private var legacySharedSkillsURL: URL!
    private var agentSkillsURL: URL!

    override func setUp() {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-LegacyImport-\(UUID().uuidString)")
        legacyLockFilePath = tempRoot.appendingPathComponent(".agents/.skill-lock.json")
        privateLockFilePath = tempRoot.appendingPathComponent(".skillsmaster/.skill-lock.json")
        privateSharedSkillsURL = tempRoot.appendingPathComponent(".skillsmaster/skills")
        legacySharedSkillsURL = tempRoot.appendingPathComponent(".agents/skills")
        agentSkillsURL = tempRoot.appendingPathComponent(".codex/skills")

        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        legacyLockFilePath = nil
        privateLockFilePath = nil
        privateSharedSkillsURL = nil
        legacySharedSkillsURL = nil
        agentSkillsURL = nil
    }

    func testImportCopiesLegacySharedSkillAndWritesPrivateLock() async throws {
        try createSkillDirectory(at: legacySharedSkillsURL.appendingPathComponent("agent-notifier"), name: "Agent Notifier")
        try writeLockFile(
            to: legacyLockFilePath,
            skills: ["agent-notifier": makeEntry(name: "agent-notifier")]
        )

        let service = makeService()
        let result = try await service.importAndMerge()

        XCTAssertEqual(result.scannedSkillCount, 1)
        XCTAssertEqual(result.importedSkillNames, ["agent-notifier"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: privateSharedSkillsURL.appendingPathComponent("agent-notifier/SKILL.md").path
            )
        )

        let privateLock = try await LockFileManager(filePath: privateLockFilePath).read()
        XCTAssertEqual(privateLock.skills["agent-notifier"]?.source, "test/skills")
    }

    func testImportFallsBackToAgentDirectoryWhenLegacySharedDirectoryIsMissing() async throws {
        try createSkillDirectory(at: agentSkillsURL.appendingPathComponent("prompt-engineering"), name: "Prompt Engineering")
        try writeLockFile(
            to: legacyLockFilePath,
            skills: ["prompt-engineering": makeEntry(name: "prompt-engineering")]
        )

        let result = try await makeService().importAndMerge()

        XCTAssertEqual(result.importedSkillNames, ["prompt-engineering"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: privateSharedSkillsURL.appendingPathComponent("prompt-engineering/SKILL.md").path
            )
        )
    }

    func testImportSkipsExistingPrivateLockEntries() async throws {
        try createSkillDirectory(at: legacySharedSkillsURL.appendingPathComponent("frontend-design"), name: "Frontend Design")
        try writeLockFile(
            to: legacyLockFilePath,
            skills: ["frontend-design": makeEntry(name: "frontend-design")]
        )
        try writeLockFile(
            to: privateLockFilePath,
            skills: [
                "frontend-design": LockEntry(
                    source: "private/source",
                    sourceType: "github",
                    sourceUrl: "https://github.com/private/source.git",
                    skillPath: "skills/frontend-design/SKILL.md",
                    skillFolderHash: "private-hash",
                    installedAt: "2026-04-01T00:00:00Z",
                    updatedAt: "2026-04-01T00:00:00Z"
                )
            ]
        )

        let result = try await makeService().importAndMerge()

        XCTAssertEqual(result.importedSkillNames, [])
        XCTAssertEqual(result.skippedExistingSkillNames, ["frontend-design"])

        let privateLock = try await LockFileManager(filePath: privateLockFilePath).read()
        XCTAssertEqual(privateLock.skills["frontend-design"]?.source, "private/source")
    }

    func testImportSkipsEntriesWithoutLocalSkillFiles() async throws {
        try writeLockFile(
            to: legacyLockFilePath,
            skills: ["missing-skill": makeEntry(name: "missing-skill")]
        )

        let result = try await makeService().importAndMerge()

        XCTAssertEqual(result.importedSkillNames, [])
        XCTAssertEqual(result.missingLocalSkillNames, ["missing-skill"])

        let privateLock = try await LockFileManager(filePath: privateLockFilePath).read()
        XCTAssertNil(privateLock.skills["missing-skill"])
    }

    private func makeService() -> LegacySkillsCLIImportService {
        LegacySkillsCLIImportService(
            legacyLockFilePath: legacyLockFilePath,
            privateLockFilePath: privateLockFilePath,
            privateSharedSkillsURL: privateSharedSkillsURL,
            legacySharedSkillsURL: legacySharedSkillsURL,
            agentSkillDirectories: [agentSkillsURL]
        )
    }

    private func createSkillDirectory(at url: URL, name: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: test
        ---
        # \(name)
        """.write(
            to: url.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeLockFile(to url: URL, skills: [String: LockEntry]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockFile = LockFile(
            version: 3,
            skills: skills,
            dismissed: [:],
            lastSelectedAgents: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(lockFile).write(to: url)
    }

    private func makeEntry(name: String) -> LockEntry {
        LockEntry(
            source: "test/skills",
            sourceType: "github",
            sourceUrl: "https://github.com/test/skills.git",
            skillPath: "skills/\(name)/SKILL.md",
            skillFolderHash: "hash-\(name)",
            installedAt: "2026-04-01T00:00:00Z",
            updatedAt: "2026-04-01T00:00:00Z"
        )
    }
}
