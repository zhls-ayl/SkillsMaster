import XCTest
@testable import SkillsMaster

@MainActor
final class ToolPreferencesStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "SkillsMasterTests.ToolPreferencesStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-ToolPreferences-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testExternalEditorPathPersists() {
        let appURL = tempDirectory.appendingPathComponent("Editor.app")
        try? FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let store = ToolPreferencesStore(defaults: defaults)
        store.setExternalEditorApp(url: appURL)

        let reloaded = ToolPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.externalEditorAppURL?.path, appURL.path)
    }

    func testDefaultTerminalAcceptsKnownBundleIdentifier() throws {
        let appURL = try makeAppBundle(name: "Warp", bundleIdentifier: KnownTerminalApp.warp.bundleIdentifier)

        let store = ToolPreferencesStore(defaults: defaults)
        try store.setDefaultTerminalApp(url: appURL)

        XCTAssertEqual(store.defaultTerminalApp, .warp)
        XCTAssertEqual(store.defaultTerminalAppPath, appURL.path)
    }

    func testDefaultTerminalRejectsUnknownBundleIdentifier() throws {
        let appURL = try makeAppBundle(name: "Unknown", bundleIdentifier: "com.example.unknown")

        let store = ToolPreferencesStore(defaults: defaults)

        XCTAssertThrowsError(try store.setDefaultTerminalApp(url: appURL)) { error in
            guard case ToolPreferencesStore.PreferenceError.unsupportedTerminalApp = error else {
                return XCTFail("Expected unsupportedTerminalApp error, got \(error)")
            }
        }
    }

    private func makeAppBundle(name: String, bundleIdentifier: String) throws -> URL {
        let appURL = tempDirectory.appendingPathComponent("\(name).app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let info: NSDictionary = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name
        ]
        try info.write(to: infoPlistURL)

        return appURL
    }
}
