import XCTest
@testable import SkillsMaster

final class SkillFileBrowserServiceTests: XCTestCase {

    private var tempDirectory: URL!
    private var skillRootURL: URL!
    private var service: SkillFileBrowserService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-SkillFiles-\(UUID().uuidString)")
        skillRootURL = tempDirectory.appendingPathComponent("sample-skill")
        service = SkillFileBrowserService()

        try FileManager.default.createDirectory(at: skillRootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        skillRootURL = nil
        service = nil
    }

    func testLoadSnapshotExcludesRootSkillMarkdownAndSystemNoise() throws {
        try createFile(at: skillRootURL.appendingPathComponent("SKILL.md"), contents: "# Home")
        try createFile(at: skillRootURL.appendingPathComponent(".DS_Store"), contents: "noise")
        try createFile(at: skillRootURL.appendingPathComponent("config.json"), contents: "{}")

        let snapshot = try service.loadSnapshot(rootURL: skillRootURL)

        XCTAssertEqual(snapshot.extraItemCount, 1)
        XCTAssertEqual(snapshot.nodes.map(\.item.name), ["config.json"])
    }

    func testLoadSnapshotBuildsNestedTreeAndCollectsWatchPaths() throws {
        try createFile(at: skillRootURL.appendingPathComponent("SKILL.md"), contents: "# Home")
        try createFile(at: skillRootURL.appendingPathComponent("docs/guide.md"), contents: "# Guide")
        try createFile(at: skillRootURL.appendingPathComponent("scripts/setup.sh"), contents: "echo hi")
        try FileManager.default.createDirectory(
            at: skillRootURL.appendingPathComponent("assets"),
            withIntermediateDirectories: true
        )

        let snapshot = try service.loadSnapshot(rootURL: skillRootURL)

        XCTAssertEqual(snapshot.nodes.map(\.item.name), ["assets", "docs", "scripts"])
        XCTAssertTrue(snapshot.hasNestedDirectories)
        XCTAssertTrue(snapshot.watchPaths.contains(skillRootURL.standardizedFileURL))
        XCTAssertTrue(snapshot.watchPaths.contains(skillRootURL.appendingPathComponent("docs").standardizedFileURL))

        let docsNode = try XCTUnwrap(snapshot.nodes.first { $0.item.name == "docs" })
        XCTAssertEqual(docsNode.children.map(\.item.name), ["guide.md"])
        XCTAssertEqual(docsNode.children.first?.item.relativePath, "docs/guide.md")
    }

    func testLoadSnapshotKeepsDirectoryBeforeFilesAndNameSortOrder() throws {
        try createFile(at: skillRootURL.appendingPathComponent("SKILL.md"), contents: "# Home")
        try createFile(at: skillRootURL.appendingPathComponent("zeta.txt"), contents: "z")
        try createFile(at: skillRootURL.appendingPathComponent("alpha.txt"), contents: "a")
        try FileManager.default.createDirectory(
            at: skillRootURL.appendingPathComponent("beta"),
            withIntermediateDirectories: true
        )

        let snapshot = try service.loadSnapshot(rootURL: skillRootURL)

        XCTAssertEqual(snapshot.nodes.map(\.item.name), ["beta", "alpha.txt", "zeta.txt"])
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
