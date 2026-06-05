import XCTest
@testable import SkillsMaster

/// `AgentType` 的单元测试。
///
/// 这些测试用于验证各个 Agent 的 computed properties 是否返回了预期值。
/// 虽然 Swift 对 `enum` 的 `switch` 已经有编译期穷尽性检查，但这里仍通过运行时测试补一层行为校验。
final class AgentTypeTests: XCTestCase {

    // MARK: - Antigravity Agent Properties

    /// Verify all computed properties of the Antigravity agent type
    func testAntigravityProperties() {
        let agent = AgentType.antigravity

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "antigravity")
        XCTAssertEqual(agent.displayName, "Antigravity")
        XCTAssertEqual(agent.detectCommand, "antigravity")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.gemini/antigravity/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.gemini/antigravity")
        XCTAssertEqual(agent.iconName, "arrow.up.circle")
        XCTAssertEqual(agent.iconResourceName, "antigravity")
        XCTAssertEqual(agent.brandColor, "indigo")

        // Antigravity does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Cursor Agent Properties

    /// Verify all computed properties of the Cursor agent type
    func testCursorProperties() {
        let agent = AgentType.cursor

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "cursor")
        XCTAssertEqual(agent.displayName, "Cursor")
        XCTAssertEqual(agent.detectCommand, "cursor")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.cursor/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.cursor")
        XCTAssertEqual(agent.iconName, "cursorarrow.rays")
        XCTAssertEqual(agent.iconResourceName, "cursor")
        XCTAssertEqual(agent.brandColor, "cyan")

        // Cursor reads Claude Code's skills directory as an additional source
        // sourceAgent is .cursor (inheritance is Cursor's own behavior)
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertEqual(additionalDirs[0].sourceAgent, .cursor)
    }

    // MARK: - Codex Agent Properties

    /// Verify all computed properties of the Codex agent type
    /// Codex has its own skills directory (~/.codex/skills/) and also reads ~/.agents/skills/ at runtime
    func testCodexProperties() {
        let agent = AgentType.codex

        XCTAssertEqual(agent.rawValue, "codex")
        XCTAssertEqual(agent.displayName, "Codex")
        XCTAssertEqual(agent.detectCommand, "codex")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.codex/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.codex")
        XCTAssertEqual(agent.iconName, "terminal")
        XCTAssertEqual(agent.iconResourceName, "codex")
        XCTAssertEqual(agent.brandColor, "green")

        // Codex also reads the legacy shared directory ~/.agents/skills/
        // sourceAgent is .codex (inheritance is Codex's own behavior)
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertEqual(additionalDirs[0].sourceAgent, .codex)
    }

    // MARK: - Gemini CLI Agent Properties

    /// Verify Gemini CLI's additionalReadableSkillsDirectories includes ~/.agents/skills/ alias
    func testGeminiCLIProperties() {
        let agent = AgentType.geminiCLI

        XCTAssertEqual(agent.rawValue, "gemini-cli")
        XCTAssertEqual(agent.displayName, "Gemini CLI")
        XCTAssertEqual(agent.detectCommand, "gemini")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.gemini/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.gemini")

        // Gemini CLI also reads ~/.agents/skills/ as a cross-agent compatibility alias
        // sourceAgent is .geminiCLI (inheritance is Gemini CLI's own behavior)
        let additionalDirs = agent.additionalReadableSkillsDirectories
        XCTAssertEqual(additionalDirs.count, 1)
        XCTAssertEqual(additionalDirs[0].sourceAgent, .geminiCLI)
    }

    // MARK: - Kiro CLI Agent Properties

    /// Verify all computed properties of the Kiro CLI agent type
    func testKiroProperties() {
        let agent = AgentType.kiroCLI

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "kiro-cli")
        XCTAssertEqual(agent.displayName, "Kiro CLI")
        XCTAssertEqual(agent.detectCommand, "kiro")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.kiro/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.kiro")
        XCTAssertEqual(agent.iconName, "k.circle")
        XCTAssertEqual(agent.iconResourceName, "kiro")
        XCTAssertEqual(agent.brandColor, "violet")

        // Kiro CLI does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - CodeBuddy Agent Properties

    /// Verify all computed properties of the CodeBuddy agent type
    func testCodeBuddyProperties() {
        let agent = AgentType.codeBuddy

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "codebuddy")
        XCTAssertEqual(agent.displayName, "CodeBuddy")
        XCTAssertEqual(agent.detectCommand, "codebuddy")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.codebuddy/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.codebuddy")
        XCTAssertEqual(agent.iconName, "c.circle")
        XCTAssertEqual(agent.iconResourceName, "codebuddy")
        XCTAssertEqual(agent.brandColor, "pink")

        // CodeBuddy does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - OpenClaw Agent Properties

    /// Verify all computed properties of the OpenClaw agent type
    func testOpenClawProperties() {
        let agent = AgentType.openClaw

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "openclaw")
        XCTAssertEqual(agent.displayName, "OpenClaw")
        XCTAssertEqual(agent.detectCommand, "openclaw")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.openclaw/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.openclaw")
        XCTAssertEqual(agent.iconName, "o.circle")
        XCTAssertEqual(agent.iconResourceName, "openclaw")
        XCTAssertEqual(agent.brandColor, "red")

        // OpenClaw does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Trae Agent Properties

    /// Verify all computed properties of the Trae agent type
    /// Trae is ByteDance's AI IDE, standalone agent with no cross-directory reading
    func testTraeProperties() {
        let agent = AgentType.trae

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "trae")
        XCTAssertEqual(agent.displayName, "Trae")
        XCTAssertEqual(agent.detectCommand, "trae")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.trae/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.trae")
        XCTAssertEqual(agent.iconName, "t.circle")
        XCTAssertEqual(agent.iconResourceName, "trae")
        XCTAssertEqual(agent.brandColor, "brightGreen")

        // Trae does not read other agents' directories (standalone agent)
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Hermes Agent Properties

    /// Verify all computed properties of the Hermes agent type
    func testHermesProperties() {
        let agent = AgentType.hermes

        // rawValue is used as the Codable key in lock file JSON
        XCTAssertEqual(agent.rawValue, "hermes")
        XCTAssertEqual(agent.displayName, "Hermes")
        XCTAssertEqual(agent.detectCommand, "hermes")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.hermes/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.hermes")
        XCTAssertEqual(agent.iconName, "h.circle")
        XCTAssertEqual(agent.iconResourceName, "hermes")
        XCTAssertEqual(agent.brandColor, "orange")

        // Hermes uses a two-level category structure, so skills are scanned one level deeper
        XCTAssertEqual(agent.maxSkillScanDepth, 2)

        // Hermes does not read other agents' directories
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - WorkBuddy Agent Properties

    func testWorkBuddyProperties() {
        let agent = AgentType.workBuddy

        XCTAssertEqual(agent.rawValue, "workbuddy")
        XCTAssertEqual(agent.displayName, "WorkBuddy")
        XCTAssertEqual(agent.detectCommand, "workbuddy")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.workbuddy/skills")
        XCTAssertEqual(agent.configDirectoryPath, "~/.workbuddy")
        XCTAssertEqual(agent.iconName, "w.circle")
        XCTAssertEqual(agent.iconResourceName, "workbuddy")
        XCTAssertEqual(agent.brandColor, "mint")
        XCTAssertEqual(agent.appBundleName, "WorkBuddy")
        XCTAssertEqual(agent.maxSkillScanDepth, 1)
        XCTAssertTrue(agent.additionalReadableSkillsDirectories.isEmpty)
    }

    // MARK: - Skill Scan Depth

    /// Verify that only Hermes uses depth 2; all other agents default to depth 1
    func testMaxSkillScanDepth() {
        for agent in AgentType.allCases {
            if agent == .hermes {
                XCTAssertEqual(agent.maxSkillScanDepth, 2, "Hermes should use scan depth 2")
            } else {
                XCTAssertEqual(agent.maxSkillScanDepth, 1, "\(agent.rawValue) should use scan depth 1")
            }
        }
    }

    // MARK: - Canonical Directory Paths

    /// Verify new canonical directory points to ~/.skillsmaster/skills/
    func testSharedSkillsDirectoryURL() {
        let url = AgentType.sharedSkillsDirectoryURL
        // Path should end with .skillsmaster/skills (not .agents/skills)
        XCTAssertTrue(url.path.hasSuffix(".skillsmaster/skills"),
                      "sharedSkillsDirectoryURL should point to ~/.skillsmaster/skills/, got: \(url.path)")
    }

    /// Verify legacy directory still points to ~/.agents/skills/
    func testLegacySharedSkillsDirectoryURL() {
        let url = AgentType.legacySharedSkillsDirectoryURL
        // Path should end with .agents/skills
        XCTAssertTrue(url.path.hasSuffix(".agents/skills"),
                      "legacySharedSkillsDirectoryURL should point to ~/.agents/skills/, got: \(url.path)")
    }

    // MARK: - CaseIterable Count

    /// Verify the total number of supported agents
    /// This test catches accidental removal of agent cases
    func testAllCasesCount() {
        // 13 agents: claudeCode, codex, geminiCLI, githubCopilot, openCode, antigravity, cursor, kiroCLI, codeBuddy, openClaw, trae, hermes, workBuddy
        XCTAssertEqual(AgentType.allCases.count, 13)
    }

    func testDisplayNameLengthSortedCasesOrdersByNameLengthThenAlphabetically() {
        let orderedNames = AgentType.displayNameLengthSortedCases.map(\.displayName)

        XCTAssertEqual(orderedNames.first, "Trae")
        XCTAssertEqual(orderedNames.last, "GitHub Copilot")

        let fiveLetterNames = orderedNames.filter { $0.count == 5 }
        XCTAssertEqual(fiveLetterNames, ["Codex"])

        let sixLetterNames = orderedNames.filter { $0.count == 6 }
        XCTAssertEqual(sixLetterNames, ["Cursor", "Hermes"])
    }

    func testGitHubCopilotRawValue() {
        let agent = AgentType.githubCopilot

        XCTAssertEqual(agent.rawValue, "github-copilot")
        XCTAssertEqual(agent.displayName, "GitHub Copilot")
        XCTAssertEqual(agent.detectCommand, "gh")
        XCTAssertEqual(agent.skillsDirectoryPath, "~/.copilot/skills")
    }

    func testDecodesLegacyAgentTypeAliases() throws {
        XCTAssertEqual(try JSONDecoder().decode(AgentType.self, from: Data("\"copilot-cli\"".utf8)), .githubCopilot)
        XCTAssertEqual(try JSONDecoder().decode(AgentType.self, from: Data("\"github-copilot\"".utf8)), .githubCopilot)
        XCTAssertEqual(try JSONDecoder().decode(AgentType.self, from: Data("\"kiro\"".utf8)), .kiroCLI)
        XCTAssertEqual(try JSONDecoder().decode(AgentType.self, from: Data("\"kiro-cli\"".utf8)), .kiroCLI)
    }

    /// Verify bundled SVG icon resource mapping for all agent types
    func testIconResourceNameMapping() {
        let expected: [AgentType: String] = [
            .claudeCode: "claude",
            .codex: "codex",
            .geminiCLI: "gemini",
            .githubCopilot: "githubcopilot",
            .openCode: "opencode",
            .antigravity: "antigravity",
            .cursor: "cursor",
            .kiroCLI: "kiro",
            .codeBuddy: "codebuddy",
            .openClaw: "openclaw",
            .trae: "trae",
            .hermes: "hermes",
            .workBuddy: "workbuddy"
        ]

        for agent in AgentType.allCases {
            XCTAssertEqual(agent.iconResourceName, expected[agent], "Unexpected icon resource for \(agent.rawValue)")
        }
    }
}
