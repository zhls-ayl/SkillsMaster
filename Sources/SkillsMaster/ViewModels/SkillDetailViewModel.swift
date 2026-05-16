import Foundation

/// SkillDetailViewModel manages the state for the Skill detail page
@MainActor
@Observable
final class SkillDetailViewModel {

    let skillManager: SkillManager
    let toolPreferences: ToolPreferencesStore

    /// Operation feedback message
    var feedbackMessage: String?

    /// F12: Whether currently checking for updates
    var isCheckingUpdate = false

    /// F12: Whether currently performing an update
    var isUpdating = false

    /// F12: Error message from update operation
    var updateError: String?

    /// F12: Check result — whether skill is up to date (for showing "Up to Date" message)
    var showUpToDate = false

    // MARK: - Link to Repository State

    /// User input repository address (supports "owner/repo" or full URL)
    var repoURLInput = ""

    /// Whether currently performing link operation (shallow clone + scan + write cache)
    var isLinking = false

    /// Error message from link operation
    var linkError: String?

    // MARK: - Batch Operation State

    /// Groups currently executing a batch operation
    var batchOperatingGroups: Set<AgentGroup> = []

    /// Whether a global (all-groups) batch operation is in progress
    var isGlobalBatchOperating: Bool = false

    /// Agent display names that failed during the last batch operation
    var batchErrors: [String] = []

    var editorViewModel: TextFileEditorViewModel?
    var pendingEditorAction: PendingEditorAction?

    init(
        skillManager: SkillManager,
        toolPreferences: ToolPreferencesStore
    ) {
        self.skillManager = skillManager
        self.toolPreferences = toolPreferences
    }

    enum PendingEditorAction {
        case close
    }

    /// Gets the latest data for a specific skill
    /// Since skills may be modified externally, always fetch the latest version from SkillManager
    func skill(id: String) -> Skill? {
        skillManager.skills.first { $0.id == id }
    }

    /// Toggle Agent assignment status
    func toggleAgent(_ agentType: AgentType, for skill: Skill) async {
        do {
            try await skillManager.toggleAssignment(skill, agent: agentType)
            feedbackMessage = nil
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    /// 在 Finder 中定位 skill 目录。
    /// 统一走 `ApplicationLauncher`，避免各处直接调用不同的 Finder API。
    func revealInFinder(skill: Skill) {
        ApplicationLauncher.revealInFinder(itemURL: skill.canonicalURL)
    }

    /// Open skill directory in Terminal
    func openInTerminal(skill: Skill) {
        do {
            try ApplicationLauncher.openInTerminal(
                directoryURL: skill.canonicalURL,
                preferences: toolPreferences
            )
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    func openInExternalEditor(skill: Skill) {
        do {
            try ApplicationLauncher.openInExternalEditor(
                itemURL: skill.skillMDURL,
                preferences: toolPreferences
            )
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    var isEditingTextFile: Bool {
        editorViewModel != nil
    }

    var hasUnsavedChangesInEditor: Bool {
        editorViewModel?.hasUnsavedChanges == true
    }

    func startEditing(skill: Skill) {
        feedbackMessage = nil
        editorViewModel = TextFileEditorViewModel(fileURL: skill.skillMDURL)
    }

    func requestCloseEditor() {
        guard let editorViewModel else { return }
        if editorViewModel.hasUnsavedChanges {
            pendingEditorAction = .close
            return
        }
        closeEditor()
    }

    func cancelPendingEditorAction() {
        pendingEditorAction = nil
    }

    func discardPendingEditorAction() {
        closeEditor()
    }

    func saveCurrentEditorAndClose() async -> Bool {
        guard let editorViewModel else { return false }
        let didSave = await editorViewModel.save()
        guard didSave else { return false }

        await skillManager.refresh()
        closeEditor()
        return true
    }

    func discardEditorForNavigation() {
        closeEditor()
    }

    private func closeEditor() {
        editorViewModel = nil
        pendingEditorAction = nil
    }

    // MARK: - F12: Update Check

    /// Check if a specific skill has an available update
    ///
    /// Calls SkillManager.checkForUpdate and updates UI state.
    /// Return value includes remoteCommitHash for generating GitHub compare URL to show diff link.
    func checkForUpdate(skill: Skill) async {
        if let sourceType = skill.lockEntry?.sourceType,
           sourceType == "local" || sourceType == "clawhub" {
            return
        }

        isCheckingUpdate = true
        updateError = nil
        showUpToDate = false

        do {
            let result = try await skillManager.checkForUpdate(skill: skill)

            // Update the corresponding skill state in SkillManager
            if let index = skillManager.skills.firstIndex(where: { $0.id == skill.id }) {
                skillManager.skills[index].hasUpdate = result.hasUpdate
                skillManager.skills[index].remoteTreeHash = result.remoteHash
                skillManager.skills[index].remoteCommitHash = result.remoteCommitHash
                skillManager.skills[index].remoteVersion = result.remoteVersion
                skillManager.updateStatuses[skill.id] = result.hasUpdate ? .hasUpdate : .upToDate

                // Update local commit hash (backfill may have been executed in checkForUpdate)
                let cachedLocalHash = await skillManager.getCachedCommitHash(for: skill.id)
                skillManager.skills[index].localCommitHash = cachedLocalHash
            }

            if !result.hasUpdate {
                showUpToDate = true
                // Auto-hide "Up to Date" message after 2 seconds
                // Task.sleep is similar to Go's time.Sleep but non-blocking
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showUpToDate = false
                }
            }
        } catch {
            updateError = error.localizedDescription
        }

        isCheckingUpdate = false
    }

    /// Execute skill update
    ///
    /// Pull latest files from remote to overwrite local, update lock entry
    func updateSkill(_ skill: Skill) async {
        isUpdating = true
        updateError = nil

        do {
            if skill.lockEntry?.sourceType == "skillhub" {
                if let remoteVersion = skill.remoteVersion {
                    try await skillManager.updateSkillsHubSkill(skill, remoteVersion: remoteVersion)
                }
            } else {
                if let remoteHash = skill.remoteTreeHash {
                    try await skillManager.updateSkill(skill, remoteHash: remoteHash)
                }
            }
        } catch {
            updateError = error.localizedDescription
        }

        isUpdating = false
    }

    // MARK: - Link to Repository

    /// Manually link skill to GitHub repository
    ///
    /// Calls SkillManager.linkSkillToRepository; after completion, refresh will automatically
    /// synthesize LockEntry from cache, and UI will switch from linkToRepoSection to lockFileSection.
    func linkToRepository(skill: Skill) async {
        let input = repoURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isLinking = true
        linkError = nil

        do {
            try await skillManager.linkSkillToRepository(skill, repoInput: input)
            // Clear input on success (UI will automatically switch to lockFileSection)
            repoURLInput = ""
        } catch {
            linkError = error.localizedDescription
        }

        isLinking = false
    }

    // MARK: - Batch Operations

    /// Whether a skill is directly installed (non-inherited) for a given agent
    private func isDirectlyInstalled(skill: Skill, agent: AgentType) -> Bool {
        skill.installations.contains { $0.agentType == agent && !$0.isInherited }
    }

    /// Whether an agent is available on the system (CLI installed or config directory exists)
    private func isAgentAvailable(_ agentType: AgentType) -> Bool {
        guard let agent = skillManager.agents.first(where: { $0.type == agentType }) else {
            return false
        }
        return agent.isInstalled || agent.configDirectoryExists
    }

    /// Re-fetch the latest skill from SkillManager (the passed-in skill may be stale after refresh()).
    private func latestSkill(_ skill: Skill) -> Skill? {
        skillManager.skills.first { $0.id == skill.id }
    }

    /// Select (assign) all available, unassigned agents in a group for the given skill
    func selectAllAgents(in group: AgentGroup, for skill: Skill) async {
        let isStandalone = !isGlobalBatchOperating
        if isStandalone {
            batchErrors = []
        }
        batchOperatingGroups.insert(group)
        defer { batchOperatingGroups.remove(group) }

        // Read latest skill state once before the batch.
        let currentSkill = latestSkill(skill) ?? skill
        var didAnyWork = false

        for agent in group.sortedAgents {
            // Skip agents that are already directly installed.
            // Note: We do NOT skip agents whose CLI is missing or config dir is absent.
            // Batch select-all is intentionally permissive — it pre-creates the agent's
            // skills directory so the skill is ready when the user installs the agent later.
            guard !isDirectlyInstalled(skill: currentSkill, agent: agent) else { continue }
            do {
                try skillManager.toggleAssignmentWithoutRefresh(currentSkill, agent: agent)
                didAnyWork = true
            } catch {
                batchErrors.append(agent.displayName)
            }
        }

        // Single refresh at the end to avoid spawning multiple syncAllRepositories tasks.
        if didAnyWork {
            await skillManager.refresh()
        }
    }

    /// Remove (unassign) all assigned agents in a group for the given skill
    func removeAllAgents(in group: AgentGroup, for skill: Skill) async {
        let isStandalone = !isGlobalBatchOperating
        if isStandalone {
            batchErrors = []
        }
        batchOperatingGroups.insert(group)
        defer { batchOperatingGroups.remove(group) }

        let currentSkill = latestSkill(skill) ?? skill
        var didAnyWork = false

        for agent in group.sortedAgents {
            guard isDirectlyInstalled(skill: currentSkill, agent: agent) else { continue }
            do {
                try skillManager.toggleAssignmentWithoutRefresh(currentSkill, agent: agent)
                didAnyWork = true
            } catch {
                batchErrors.append(agent.displayName)
            }
        }

        if didAnyWork {
            await skillManager.refresh()
        }
    }

    /// Select (assign) all available, unassigned agents across all groups for the given skill
    func selectAllAgents(for skill: Skill) async {
        isGlobalBatchOperating = true
        batchErrors = []
        defer { isGlobalBatchOperating = false }

        let currentSkill = latestSkill(skill) ?? skill
        var didAnyWork = false

        for agent in AgentType.allCases {
            guard !isDirectlyInstalled(skill: currentSkill, agent: agent) else { continue }
            do {
                try skillManager.toggleAssignmentWithoutRefresh(currentSkill, agent: agent)
                didAnyWork = true
            } catch {
                batchErrors.append(agent.displayName)
            }
        }

        if didAnyWork {
            await skillManager.refresh()
        }
    }

    /// Remove (unassign) all assigned agents across all groups for the given skill
    func removeAllAgents(for skill: Skill) async {
        isGlobalBatchOperating = true
        batchErrors = []
        defer { isGlobalBatchOperating = false }

        let currentSkill = latestSkill(skill) ?? skill
        var didAnyWork = false

        for agent in AgentType.allCases {
            guard isDirectlyInstalled(skill: currentSkill, agent: agent) else { continue }
            do {
                try skillManager.toggleAssignmentWithoutRefresh(currentSkill, agent: agent)
                didAnyWork = true
            } catch {
                batchErrors.append(agent.displayName)
            }
        }

        if didAnyWork {
            await skillManager.refresh()
        }
    }
}
