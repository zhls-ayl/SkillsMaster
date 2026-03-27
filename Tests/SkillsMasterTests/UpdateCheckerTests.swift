import XCTest
@testable import SkillsMaster

final class UpdateCheckerTests: XCTestCase {

    func testResolveInstallationContextForWritableAppBundle() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appURL = tempRoot.appendingPathComponent("SkillsMaster.app")

        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let context = try UpdateChecker.resolveInstallationContext(
            bundleURL: appURL,
            fileManager: fileManager,
            relaunchUserID: 501,
            relaunchUserName: "andy"
        )

        XCTAssertEqual(context.appBundleURL, appURL.standardizedFileURL)
        XCTAssertFalse(context.requiresAdminPrivileges)
        XCTAssertEqual(context.relaunchUserID, 501)
        XCTAssertEqual(context.relaunchUserName, "andy")
    }

    func testResolveInstallationContextRequiresAdminWhenParentDirectoryIsNotWritable() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appURL = tempRoot.appendingPathComponent("SkillsMaster.app")

        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempRoot.path)
            try? fileManager.removeItem(at: tempRoot)
        }

        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempRoot.path)

        let context = try UpdateChecker.resolveInstallationContext(
            bundleURL: appURL,
            fileManager: fileManager,
            relaunchUserID: 501,
            relaunchUserName: "andy"
        )

        XCTAssertTrue(context.requiresAdminPrivileges)
    }

    func testResolveInstallationContextRejectsNonAppBundle() {
        let executableURL = URL(fileURLWithPath: "/tmp/SkillsMaster")

        XCTAssertThrowsError(
            try UpdateChecker.resolveInstallationContext(
                bundleURL: executableURL,
                relaunchUserID: 501,
                relaunchUserName: "andy"
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdateInstallError, .notRunningFromAppBundle)
        }
    }

    func testResolveInstallationContextRejectsTranslocatedApp() {
        let translocatedURL = URL(fileURLWithPath: "/private/var/folders/demo/AppTranslocation/1234/d/SkillsMaster.app")

        XCTAssertThrowsError(
            try UpdateChecker.resolveInstallationContext(
                bundleURL: translocatedURL,
                relaunchUserID: 501,
                relaunchUserName: "andy"
            )
        ) { error in
            XCTAssertEqual(
                error as? AppUpdateInstallError,
                .translocatedApp(path: translocatedURL.standardizedFileURL.path)
            )
        }
    }

    func testMakeUpdateScriptIncludesBackupAndRelaunchSteps() {
        let script = UpdateChecker.makeUpdateScript(
            currentPID: 42,
            targetAppPath: "/Applications/SkillsMaster.app",
            newAppPath: "/tmp/SkillsMasterExtract/SkillsMaster.app",
            extractDir: "/tmp/SkillsMasterExtract",
            downloadDir: "/tmp/SkillsMasterUpdate",
            relaunchUserID: 501,
            relaunchUserName: "andy"
        )

        XCTAssertTrue(script.contains("BACKUP_APP=\"${TARGET_APP}.backup\""))
        XCTAssertTrue(script.contains("mv \"$TARGET_APP\" \"$BACKUP_APP\""))
        XCTAssertTrue(script.contains("launchctl asuser \"$ORIGINAL_UID\" open \"$TARGET_APP\""))
        XCTAssertTrue(script.contains("/usr/bin/sudo -u \"$ORIGINAL_USER\" open \"$TARGET_APP\""))
    }
}
