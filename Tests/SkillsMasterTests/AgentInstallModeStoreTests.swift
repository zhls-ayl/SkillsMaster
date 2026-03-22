import XCTest
@testable import SkillsMaster

final class AgentInstallModeStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: AgentInstallModeStore!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SkillsMasterTests.AgentInstallModeStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = AgentInstallModeStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testModeFallsBackToSymlinkWhenNoPreferenceExists() {
        XCTAssertEqual(store.mode(for: .codex), .symlink)
        XCTAssertEqual(store.mode(for: .claudeCode), .symlink)
    }

    func testLoadAllReflectsPersistedPerAgentModes() {
        store.setMode(.copy, for: .codex)
        store.setMode(.symlink, for: .cursor)

        let allModes = store.loadAll()

        XCTAssertEqual(allModes[.codex], .copy)
        XCTAssertEqual(allModes[.cursor], .symlink)
        XCTAssertEqual(allModes[.openClaw], .symlink)
    }
}
