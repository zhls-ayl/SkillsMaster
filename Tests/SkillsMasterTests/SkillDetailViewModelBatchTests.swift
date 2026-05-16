import XCTest
@testable import SkillsMaster

/// Batch operation tests for `SkillDetailViewModel`.
///
/// Since `SkillManager` is a `final class` without a protocol, these tests exercise
/// the real SkillManager. By populating `skillManager.agents` to report availability
/// and constructing skills with specific installations, we can verify:
/// - State management (`batchOperatingGroups`, `isGlobalBatchOperating`, `batchErrors`)
/// - Error resilience (Property 6): when toggleAssignment fails for some agents,
///   the operation continues and collects error names.
///
/// Feature: skill-detail-agent-assignment-grouping, Property 6: 批量操作容错性
/// Validates: Requirements 2.4, 3.5, 4.7
@MainActor
final class SkillDetailViewModelBatchTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal Skill for testing.
    private func makeSkill(
        id: String = "test-skill",
        installations: [SkillInstallation] = []
    ) -> Skill {
        Skill(
            id: id,
            canonicalURL: URL(fileURLWithPath: "/tmp/test-skills/\(id)"),
            metadata: SkillMetadata(
                name: "Test Skill",
                description: "A test skill"
            ),
            markdownBody: "# Test",
            scope: .unassigned,
            installations: installations
        )
    }

    /// Create a SkillInstallation for a given agent (direct, non-inherited).
    private func makeInstallation(agent: AgentType) -> SkillInstallation {
        SkillInstallation(
            agentType: agent,
            path: URL(fileURLWithPath: "/tmp/fake/\(agent.rawValue)/test-skill"),
            isSymlink: true,
            isInherited: false,
            inheritedFrom: nil
        )
    }

    /// Create a viewModel with agents marked as available (configDirectoryExists = true).
    private func makeViewModel(availableAgents: [AgentType] = AgentType.allCases) -> (SkillDetailViewModel, SkillManager) {
        let skillManager = SkillManager()
        // Mark the specified agents as "available" so batch operations don't skip them.
        skillManager.agents = availableAgents.map { agentType in
            Agent(
                type: agentType,
                isInstalled: false,
                configDirectoryExists: true,
                skillsDirectoryExists: true,
                skillCount: 0
            )
        }
        let viewModel = SkillDetailViewModel(
            skillManager: skillManager,
            toolPreferences: ToolPreferencesStore()
        )
        return (viewModel, skillManager)
    }

    // MARK: - selectAllAgents(in:for:) Tests

    /// selectAllAgents should attempt to install all uninstalled, available agents in the group.
    /// Since file system paths don't exist, toggleAssignment will fail for each agent,
    /// and their names should appear in batchErrors.
    func testSelectAllAgents_collectsErrorsForFailedAgents() async {
        let (viewModel, _) = makeViewModel()
        let group = AgentGroup.google  // contains geminiCLI, antigravity
        let skill = makeSkill()  // no installations → all agents are "uninstalled"

        await viewModel.selectAllAgents(in: group, for: skill)

        // All agents in the group should have failed (no real file system)
        // and their display names should be in batchErrors.
        let expectedNames = Set(group.sortedAgents.map(\.displayName))
        let actualNames = Set(viewModel.batchErrors)
        XCTAssertEqual(
            actualNames, expectedNames,
            "batchErrors should contain all agents that failed during selectAll. Got: \(viewModel.batchErrors)"
        )
    }

    /// selectAllAgents should skip agents that are already directly installed.
    func testSelectAllAgents_skipsAlreadyInstalledAgents() async {
        let group = AgentGroup.google  // geminiCLI, antigravity
        let alreadyInstalled = group.sortedAgents.first!
        let (viewModel, _) = makeViewModel()
        let skill = makeSkill(installations: [makeInstallation(agent: alreadyInstalled)])

        await viewModel.selectAllAgents(in: group, for: skill)

        // The already-installed agent should NOT be in batchErrors
        // (it was skipped, not attempted)
        XCTAssertFalse(
            viewModel.batchErrors.contains(alreadyInstalled.displayName),
            "Already-installed agent '\(alreadyInstalled.displayName)' should be skipped, not appear in errors"
        )
    }

    /// selectAllAgents should skip agents that are not available on the system.
    func testSelectAllAgents_skipsUnavailableAgents() async {
        let group = AgentGroup.google  // geminiCLI, antigravity
        // Only make one agent available
        let availableAgent = group.sortedAgents.first!
        let (viewModel, _) = makeViewModel(availableAgents: [availableAgent])
        let skill = makeSkill()

        await viewModel.selectAllAgents(in: group, for: skill)

        // Only the available agent should have been attempted (and failed)
        XCTAssertEqual(viewModel.batchErrors.count, 1)
        XCTAssertEqual(viewModel.batchErrors.first, availableAgent.displayName)
    }

    // MARK: - removeAllAgents(in:for:) Tests

    /// removeAllAgents should attempt to remove all directly-installed agents in the group.
    func testRemoveAllAgents_collectsErrorsForFailedAgents() async {
        let group = AgentGroup.byteDance  // trae, traeCN
        let (viewModel, _) = makeViewModel()
        // Mark all agents in group as installed
        let installations = group.sortedAgents.map { makeInstallation(agent: $0) }
        let skill = makeSkill(installations: installations)

        await viewModel.removeAllAgents(in: group, for: skill)

        // All should have been attempted and failed
        let expectedNames = Set(group.sortedAgents.map(\.displayName))
        let actualNames = Set(viewModel.batchErrors)
        XCTAssertEqual(
            actualNames, expectedNames,
            "batchErrors should contain all agents that failed during removeAll. Got: \(viewModel.batchErrors)"
        )
    }

    /// removeAllAgents should skip agents that are NOT directly installed.
    func testRemoveAllAgents_skipsUninstalledAgents() async {
        let group = AgentGroup.byteDance  // trae, traeCN
        let (viewModel, _) = makeViewModel()
        // Only install one agent
        let installedAgent = group.sortedAgents.first!
        let skill = makeSkill(installations: [makeInstallation(agent: installedAgent)])

        await viewModel.removeAllAgents(in: group, for: skill)

        // Only the installed agent should have been attempted
        XCTAssertEqual(viewModel.batchErrors.count, 1)
        XCTAssertEqual(viewModel.batchErrors.first, installedAgent.displayName)
    }

    // MARK: - State Management Tests

    /// batchOperatingGroups should be empty before and after the operation.
    func testBatchOperatingGroups_clearedAfterOperation() async {
        let (viewModel, _) = makeViewModel()
        let group = AgentGroup.anthropic
        let skill = makeSkill()

        XCTAssertTrue(viewModel.batchOperatingGroups.isEmpty, "Should start empty")

        await viewModel.selectAllAgents(in: group, for: skill)

        XCTAssertFalse(
            viewModel.batchOperatingGroups.contains(group),
            "batchOperatingGroups should not contain the group after operation completes"
        )
        XCTAssertTrue(viewModel.batchOperatingGroups.isEmpty)
    }

    /// isGlobalBatchOperating should be false after global operation completes.
    func testIsGlobalBatchOperating_clearedAfterGlobalOperation() async {
        let (viewModel, _) = makeViewModel()
        let skill = makeSkill()

        XCTAssertFalse(viewModel.isGlobalBatchOperating)

        await viewModel.selectAllAgents(for: skill)

        XCTAssertFalse(
            viewModel.isGlobalBatchOperating,
            "isGlobalBatchOperating should be false after global selectAll completes"
        )
    }

    /// Global removeAllAgents should clear isGlobalBatchOperating after completion.
    func testGlobalRemoveAllAgents_clearedAfterOperation() async {
        let (viewModel, _) = makeViewModel()
        let installations = AgentType.allCases.map { makeInstallation(agent: $0) }
        let skill = makeSkill(installations: installations)

        await viewModel.removeAllAgents(for: skill)

        XCTAssertFalse(viewModel.isGlobalBatchOperating)
    }

    // MARK: - Error Resilience (Property 6)

    /// Property 6: If a subset of agents fail, the operation still processes ALL remaining agents.
    /// We verify this by having a mix of installed/uninstalled agents in a multi-agent group.
    /// For selectAll: only uninstalled agents are attempted. All attempted ones should fail
    /// (due to missing file system) and appear in batchErrors.
    func testErrorResilience_allRemainingAgentsProcessedDespiteFailures() async {
        let group = AgentGroup.independent  // openCode, openClaw (2 agents)
        let (viewModel, _) = makeViewModel()
        let skill = makeSkill()  // none installed, so selectAll will attempt both

        await viewModel.selectAllAgents(in: group, for: skill)

        // Both agents should have been attempted (not short-circuited after first failure)
        XCTAssertEqual(
            viewModel.batchErrors.count, group.sortedAgents.count,
            "All agents should have been attempted despite failures. Expected \(group.sortedAgents.count), got \(viewModel.batchErrors.count)"
        )
    }

    /// Property 6: batchErrors contains exactly the names of the failed agents.
    func testErrorResilience_batchErrorsContainsExactFailedNames() async {
        let group = AgentGroup.tencent  // codeBuddy, workBuddy
        let (viewModel, _) = makeViewModel()
        let skill = makeSkill()

        await viewModel.selectAllAgents(in: group, for: skill)

        // Verify the error list contains the display names of all agents in the group
        for agent in group.sortedAgents {
            XCTAssertTrue(
                viewModel.batchErrors.contains(agent.displayName),
                "batchErrors should contain '\(agent.displayName)'"
            )
        }
        // And no extra entries
        XCTAssertEqual(viewModel.batchErrors.count, group.sortedAgents.count)
    }

    /// batchErrors is reset at the start of each batch operation.
    func testBatchErrors_resetAtStartOfEachOperation() async {
        let (viewModel, _) = makeViewModel()
        let skill = makeSkill()

        // First operation: selectAll on one group
        await viewModel.selectAllAgents(in: .anthropic, for: skill)
        XCTAssertFalse(viewModel.batchErrors.isEmpty, "Should have errors from first operation")

        // Second operation: selectAll on another group
        await viewModel.selectAllAgents(in: .openAI, for: skill)

        // batchErrors should only contain errors from the second operation
        // (the anthropic agent names should be gone)
        let anthropicNames = AgentGroup.anthropic.sortedAgents.map(\.displayName)
        for name in anthropicNames {
            XCTAssertFalse(
                viewModel.batchErrors.contains(name),
                "batchErrors should not contain '\(name)' from previous operation"
            )
        }
    }
}
