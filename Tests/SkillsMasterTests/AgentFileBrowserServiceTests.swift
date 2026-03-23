import XCTest
@testable import SkillsMaster

final class AgentFileBrowserServiceTests: XCTestCase {

    private var tempDirectory: URL!
    private var rootURL: URL!
    private var protectedURL: URL!
    private var service: AgentFileBrowserService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-AgentFiles-\(UUID().uuidString)")
        rootURL = tempDirectory.appendingPathComponent(".codex")
        protectedURL = rootURL.appendingPathComponent("skills")
        service = AgentFileBrowserService()

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        rootURL = nil
        protectedURL = nil
        service = nil
    }

    func testLoadTreeIncludesHiddenFilesAndMarksSkillsSubtreeProtected() throws {
        try createFile(at: rootURL.appendingPathComponent(".env"), contents: "OPENAI_API_KEY=test")
        try createFile(at: rootURL.appendingPathComponent("settings.json"), contents: "{}")
        try FileManager.default.createDirectory(
            at: protectedURL.appendingPathComponent("sample-skill"),
            withIntermediateDirectories: true
        )
        try createFile(
            at: protectedURL.appendingPathComponent("sample-skill/SKILL.md"),
            contents: "# skill"
        )

        let snapshot = service.loadTree(rootURL: rootURL, protectedURL: protectedURL)

        XCTAssertTrue(snapshot.rootExists)

        let envFile = try XCTUnwrap(snapshot.entries.first { $0.name == ".env" })
        XCTAssertTrue(envFile.isHidden)
        XCTAssertFalse(envFile.isProtected)

        let skillsDirectory = try XCTUnwrap(snapshot.entries.first { $0.name == "skills" })
        XCTAssertTrue(skillsDirectory.isProtected)

        let protectedChild = try XCTUnwrap(skillsDirectory.children?.first { $0.name == "sample-skill" })
        XCTAssertTrue(protectedChild.isProtected)
        XCTAssertEqual(
            protectedChild.protectionReason,
            "`skills/` 目录及其子内容由 SkillsMaster 管理，在 Agent Files 中只读。"
        )
    }

    func testCreateRejectsReservedSkillsPath() throws {
        XCTAssertThrowsError(
            try service.createItem(
                named: "skills",
                kind: .folder,
                in: rootURL,
                rootURL: rootURL,
                protectedURL: protectedURL
            )
        ) { error in
            guard case AgentFileBrowserService.BrowserError.protectedPath(let reason) = error else {
                return XCTFail("Expected protectedPath error, got \(error)")
            }
            XCTAssertTrue(reason.contains("`skills/`"))
        }
    }

    func testRenameAndDeleteRejectProtectedItems() throws {
        let protectedFileURL = protectedURL.appendingPathComponent("sample-skill/config.json")
        try createFile(at: protectedFileURL, contents: "{}")

        XCTAssertThrowsError(
            try service.renameItem(
                at: protectedFileURL,
                to: "renamed.json",
                rootURL: rootURL,
                protectedURL: protectedURL
            )
        ) { error in
            guard case AgentFileBrowserService.BrowserError.protectedPath = error else {
                return XCTFail("Expected protectedPath error, got \(error)")
            }
        }

        XCTAssertThrowsError(
            try service.deleteItem(
                at: protectedFileURL,
                rootURL: rootURL,
                protectedURL: protectedURL
            )
        ) { error in
            guard case AgentFileBrowserService.BrowserError.protectedPath = error else {
                return XCTFail("Expected protectedPath error, got \(error)")
            }
        }
    }

    func testCreateRenameDeleteAndReplaceInRegularDirectory() throws {
        let configsDirectory = try service.createItem(
            named: "configs",
            kind: .folder,
            in: rootURL,
            rootURL: rootURL,
            protectedURL: protectedURL
        )

        let createdFile = try service.createItem(
            named: "settings.json",
            kind: .file,
            in: configsDirectory,
            rootURL: rootURL,
            protectedURL: protectedURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdFile.path))

        XCTAssertThrowsError(
            try service.createItem(
                named: "settings.json",
                kind: .file,
                in: configsDirectory,
                rootURL: rootURL,
                protectedURL: protectedURL
            )
        ) { error in
            guard case AgentFileBrowserService.BrowserError.itemAlreadyExists = error else {
                return XCTFail("Expected itemAlreadyExists error, got \(error)")
            }
        }

        let replacedFile = try service.createItem(
            named: "settings.json",
            kind: .file,
            in: configsDirectory,
            rootURL: rootURL,
            protectedURL: protectedURL,
            replaceExisting: true
        )
        XCTAssertEqual(replacedFile.lastPathComponent, "settings.json")

        let renamedFile = try service.renameItem(
            at: replacedFile,
            to: "preferences.json",
            rootURL: rootURL,
            protectedURL: protectedURL
        )
        XCTAssertEqual(renamedFile.lastPathComponent, "preferences.json")

        try service.deleteItem(at: renamedFile, rootURL: rootURL, protectedURL: protectedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedFile.path))
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
