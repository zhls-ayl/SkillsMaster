import Foundation
import Observation

/// ViewModel for SkillsHub marketplace browsing, detail loading, install, and update affordances.
@MainActor
@Observable
final class SkillsHubBrowserViewModel {

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var searchText = ""
    var selectedCategory: SkillsHubCategory?
    var selectedSort: SkillsHubService.SkillSort = .score

    var displayedSkills: [SkillsHubSkill] = []
    var isLoading = false
    var errorMessage: String?

    var currentPage = 1
    var totalCount = 0

    var selectedSkillID: String? {
        didSet {
            guard oldValue != selectedSkillID else { return }
            syncSelectedTargetAgentsForCurrentSelection()
        }
    }
    var selectedSkillDetail: SkillsHubSkillDetail?
    var isLoadingDetail = false
    var detailError: String?

    var selectedTargetAgents: Set<AgentType> = []

    var installingSkillSlug: String?
    var installingStatusMessage: String?
    var notice: Notice?

    var isSearchActive: Bool {
        normalizedSearchText != nil
    }

    var totalPages: Int {
        guard totalCount > 0 else { return 1 }
        return max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
    }

    var selectedSkill: SkillsHubSkill? {
        guard let selectedSkillID else { return nil }
        return displayedSkills.first { $0.id == selectedSkillID }
    }

    var targetAgentTypes: [AgentType] {
        AgentType.displayNameLengthSortedCases
    }

    private let service: any SkillsHubServiceProtocol
    private let skillManager: SkillManager

    private var installedSkillsHubSlugs = Set<String>()
    private var installedSkillIDsNoSource = Set<String>()
    private var featuredSlugs = Set<String>()
    private var hasLoadedInitialPage = false
    private var listRequestVersion = 0
    private var searchTask: Task<Void, Never>?

    private let pageSize = 24

    init(
        skillManager: SkillManager,
        service: any SkillsHubServiceProtocol = SkillsHubService()
    ) {
        self.skillManager = skillManager
        self.service = service
    }

    func onAppear() async {
        syncInstalledSkills()

        guard !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true

        await loadFeaturedIfNeeded()
        await reloadCurrentList()
    }

    func refresh() async {
        syncInstalledSkills()
        await service.clearCache()
        await loadFeaturedIfNeeded(force: true)
        await reloadCurrentList()
    }

    func onSearchTextChanged() {
        searchTask?.cancel()
        currentPage = 1

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await reloadCurrentList()
        }
    }

    func selectCategory(_ category: SkillsHubCategory?) {
        guard selectedCategory?.rawValue != category?.rawValue else { return }
        selectedCategory = category
        currentPage = 1
        Task { await reloadCurrentList() }
    }

    func selectSort(_ sort: SkillsHubService.SkillSort) {
        guard selectedSort != sort else { return }
        selectedSort = sort
        currentPage = 1
        Task { await reloadCurrentList() }
    }

    func goToNextPage() {
        guard currentPage < totalPages else { return }
        currentPage += 1
        Task { await reloadCurrentList() }
    }

    func goToPreviousPage() {
        guard currentPage > 1 else { return }
        currentPage -= 1
        Task { await reloadCurrentList() }
    }

    func goToPage(_ page: Int) {
        let clamped = min(max(1, page), totalPages)
        guard clamped != currentPage else { return }
        currentPage = clamped
        Task { await reloadCurrentList() }
    }

    func syncInstalledSkills() {
        installedSkillsHubSlugs = Set(
            skillManager.skills.compactMap { skill in
                guard skill.lockEntry?.sourceType == "skillhub" else { return nil }
                return skill.lockEntry?.source
            }
        )

        installedSkillIDsNoSource = Set(
            skillManager.skills.compactMap { skill in
                guard skill.lockEntry == nil else { return nil }
                return skill.id
            }
        )
    }

    func isInstalled(_ skill: SkillsHubSkill) -> Bool {
        matchingInstalledSkill(for: skill) != nil
    }

    func canReinstall(_ skill: SkillsHubSkill) -> Bool {
        installedSkillsHubSlugs.contains(skill.slug)
    }

    func isInstalling(_ skill: SkillsHubSkill) -> Bool {
        installingSkillSlug == skill.slug
    }

    func isFeatured(_ skill: SkillsHubSkill) -> Bool {
        featuredSlugs.contains(skill.slug)
    }

    func installButtonTitle(for skill: SkillsHubSkill) -> String {
        if isInstalling(skill) {
            return installingStatusMessage ?? "Installing..."
        }
        return installAction(for: skill).title
    }

    func detailInstallButtonTitle(for skill: SkillsHubSkill) -> String {
        if isInstalling(skill) {
            return installingStatusMessage ?? "Installing..."
        }
        return installAction(for: skill).title
    }

    func detailInstallButtonSystemImage(for skill: SkillsHubSkill) -> String {
        installAction(for: skill).systemImage
    }

    func toggleTargetAgent(_ agent: AgentType) {
        if selectedTargetAgents.contains(agent) {
            selectedTargetAgents.remove(agent)
        } else {
            selectedTargetAgents.insert(agent)
        }
    }

    func isAgentDetected(_ agent: AgentType) -> Bool {
        skillManager.agents.first { $0.type == agent }?.supportsRootFileManagement == true
    }

    func targetSelectionSummary() -> String {
        let count = selectedTargetAgents.count
        if count == 0 {
            return AppLocalization.string("No Agent Selected")
        }
        if count == 1 {
            return AppLocalization.string("1 Agent Selected")
        }
        return AppLocalization.format("%d Agents Selected", count)
    }

    func isShowingManualTranslation(for skillID: String) -> Bool {
        skillManager.isShowingManualTranslation(for: manualTranslationKey(for: skillID))
    }

    func toggleManualTranslation(for skillID: String) {
        skillManager.toggleManualTranslation(for: manualTranslationKey(for: skillID))
    }

    func loadSelection(for skill: SkillsHubSkill) async {
        selectedSkillDetail = nil
        detailError = nil
        isLoadingDetail = true

        let targetSkillID = skill.id

        do {
            let detail = try await service.fetchSkillDetail(slug: skill.slug, seed: skill)
            guard selectedSkillID == targetSkillID else { return }
            selectedSkillDetail = detail
        } catch {
            guard selectedSkillID == targetSkillID else { return }
            detailError = error.localizedDescription
        }

        isLoadingDetail = false
    }

    func installSkill(_ skill: SkillsHubSkill) {
        guard installingSkillSlug == nil else { return }
        guard !selectedTargetAgents.isEmpty else {
            notice = Notice(
                title: AppLocalization.string("Unable to Install"),
                message: AppLocalization.string("Select at least one target Agent.")
            )
            return
        }

        Task { await performInstall(skill) }
    }

    private func performInstall(_ skill: SkillsHubSkill) async {
        let action = installAction(for: skill)
        let targetAgents = selectedTargetAgents
        installingSkillSlug = skill.slug
        installingStatusMessage = AppLocalization.string("Loading package...")
        defer {
            installingSkillSlug = nil
            installingStatusMessage = nil
        }

        do {
            let detail = try await resolvedDetail(for: skill)
            guard let version = detail.installVersion else {
                throw SkillManager.ImportError.parseFailed("SkillsHub did not provide a version for \(skill.slug).")
            }

            installingStatusMessage = AppLocalization.string("Downloading archive...")
            let archiveData = try await service.downloadSkillArchive(slug: skill.slug)

            installingStatusMessage = AppLocalization.string("Installing...")
            try await skillManager.installSkillsHubSkill(
                skill: detail.skill,
                version: version,
                archiveData: archiveData,
                targetAgents: targetAgents
            )

            syncInstalledSkills()
            notice = Notice(
                title: action.completionTitle,
                message: AppLocalization.format("%@ was installed to %d Agent(s).", skill.name, targetAgents.count)
            )
        } catch {
            notice = Notice(title: AppLocalization.string("Installation Failed"), message: error.localizedDescription)
        }
    }

    private func resolvedDetail(for skill: SkillsHubSkill) async throws -> SkillsHubSkillDetail {
        if let selectedSkillDetail, selectedSkillDetail.skill.slug == skill.slug {
            return selectedSkillDetail
        }
        return try await service.fetchSkillDetail(slug: skill.slug, seed: skill)
    }

    private func installAction(for skill: SkillsHubSkill) -> MarketplaceInstallAction {
        let fallback: MarketplaceInstallAction = isInstalled(skill) ? .reinstall : .install
        return MarketplaceInstallAction.resolve(
            selectedAgents: selectedTargetAgents,
            directInstalledAgents: directInstalledAgents(for: skill),
            fallbackWhenSelectionEmpty: fallback
        )
    }

    private func directInstalledAgents(for skill: SkillsHubSkill) -> Set<AgentType> {
        guard let installedSkill = matchingInstalledSkill(for: skill) else {
            return []
        }

        return Set(
            installedSkill.installations
                .filter { !$0.isInherited }
                .map(\.agentType)
        )
    }

    private func matchingInstalledSkill(for skill: SkillsHubSkill) -> Skill? {
        if installedSkillsHubSlugs.contains(skill.slug) {
            return skillManager.skills.first {
                $0.id == skill.slug &&
                $0.lockEntry?.sourceType == "skillhub" &&
                $0.lockEntry?.source == skill.slug
            }
        }

        if installedSkillIDsNoSource.contains(skill.slug) {
            return skillManager.skills.first {
                $0.id == skill.slug && $0.lockEntry == nil
            }
        }

        return nil
    }

    private func syncSelectedTargetAgentsForCurrentSelection() {
        guard let selectedSkill else {
            selectedTargetAgents.removeAll()
            return
        }
        selectedTargetAgents = directInstalledAgents(for: selectedSkill)
    }

    private func loadFeaturedIfNeeded(force: Bool = false) async {
        guard force || featuredSlugs.isEmpty else { return }
        do {
            let featured = try await service.fetchFeaturedSkills()
            featuredSlugs = Set(featured.map(\.slug))
        } catch {
            // Feature badge is optional for the first version. Ignore failure quietly.
        }
    }

    private func reloadCurrentList() async {
        listRequestVersion += 1
        let requestVersion = listRequestVersion

        isLoading = true
        errorMessage = nil

        do {
            let page = try await service.fetchSkills(options: browseOptions)
            guard requestVersion == listRequestVersion else { return }

            displayedSkills = page.items
            totalCount = page.total
            updateSelection(afterLoading: page.items)
        } catch {
            guard requestVersion == listRequestVersion else { return }

            displayedSkills = []
            totalCount = 0
            selectedSkillID = nil
            errorMessage = error.localizedDescription
        }

        guard requestVersion == listRequestVersion else { return }
        isLoading = false
    }

    private var browseOptions: SkillsHubService.BrowseOptions {
        SkillsHubService.BrowseOptions(
            page: currentPage,
            pageSize: pageSize,
            sort: selectedSort,
            direction: .descending,
            keyword: normalizedSearchText,
            category: selectedCategory
        )
    }

    private var normalizedSearchText: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func manualTranslationKey(for skillID: String) -> String {
        "skillshub:\(skillID)"
    }

    private func updateSelection(afterLoading skills: [SkillsHubSkill]) {
        if let selectedSkillID,
           skills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        selectedSkillID = skills.first?.id
    }
}
