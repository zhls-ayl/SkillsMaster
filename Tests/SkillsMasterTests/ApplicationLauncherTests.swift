import XCTest
@testable import SkillsMaster

final class ApplicationLauncherTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMasterApplicationLauncherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testFinderRevealURLReturnsOriginalURLWhenPathExists() throws {
        let skillDir = tempDir.appendingPathComponent("demo-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let revealURL = ApplicationLauncher.finderRevealURL(for: skillDir)

        XCTAssertEqual(revealURL.standardizedFileURL.path, skillDir.standardizedFileURL.path)
    }

    func testFinderRevealURLFallsBackToNearestExistingParent() throws {
        let skillDir = tempDir.appendingPathComponent("demo-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let missingSkillFile = skillDir.appendingPathComponent("missing/SKILL.md")

        let revealURL = ApplicationLauncher.finderRevealURL(for: missingSkillFile)

        XCTAssertEqual(revealURL.standardizedFileURL.path, skillDir.standardizedFileURL.path)
    }
}
