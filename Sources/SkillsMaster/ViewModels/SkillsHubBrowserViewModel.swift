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

    var selectedSkillID: String?
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
        initializeSelectedAgentsIfNeeded()

        guard !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true

        await loadFeaturedIfNeeded()
        await reloadCurrentList()
    }

    func refresh() async {
        syncInstalledSkills()
        initializeSelectedAgentsIfNeeded()
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
        if installedSkillsHubSlugs.contains(skill.slug) {
            return true
        }
        return installedSkillIDsNoSource.contains(skill.slug)
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
        if canReinstall(skill) {
            return "Reinstall"
        }
        return "Install"
    }

    func detailInstallButtonTitle(for skill: SkillsHubSkill) -> String {
        if isInstalling(skill) {
            return installingStatusMessage ?? "Installing..."
        }
        if canReinstall(skill) {
            return "Reinstall"
        }
        return "Install"
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
        return count == 1 ? "1 个 Agent 已选中" : "\(count) 个 Agent 已选中"
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
            notice = Notice(title: "无法安装", message: "请至少选择一个目标 Agent。")
            return
        }

        Task { await performInstall(skill) }
    }

    private func performInstall(_ skill: SkillsHubSkill) async {
        let wasReinstall = canReinstall(skill)
        installingSkillSlug = skill.slug
        installingStatusMessage = "Loading package..."
        defer {
            installingSkillSlug = nil
            installingStatusMessage = nil
        }

        do {
            let detail = try await resolvedDetail(for: skill)
            guard let version = detail.installVersion else {
                throw SkillManager.ImportError.parseFailed("SkillsHub did not provide a version for \(skill.slug).")
            }

            installingStatusMessage = "Downloading archive..."
            let archiveData = try await service.downloadSkillArchive(slug: skill.slug)

            installingStatusMessage = "Installing..."
            try await skillManager.installSkillsHubSkill(
                skill: detail.skill,
                version: version,
                archiveData: archiveData,
                targetAgents: selectedTargetAgents
            )

            syncInstalledSkills()
            notice = Notice(
                title: wasReinstall ? "Reinstall Complete" : "Install Complete",
                message: "\(skill.name) 已安装到 \(selectedTargetAgents.count) 个 Agent。"
            )
        } catch {
            notice = Notice(title: "Installation Failed", message: error.localizedDescription)
        }
    }

    private func resolvedDetail(for skill: SkillsHubSkill) async throws -> SkillsHubSkillDetail {
        if let selectedSkillDetail, selectedSkillDetail.skill.slug == skill.slug {
            return selectedSkillDetail
        }
        return try await service.fetchSkillDetail(slug: skill.slug, seed: skill)
    }

    private func initializeSelectedAgentsIfNeeded() {
        guard selectedTargetAgents.isEmpty else { return }

        let detected = Set(
            skillManager.agents
                .filter(\.supportsRootFileManagement)
                .map(\.type)
        )
        selectedTargetAgents = detected.isEmpty ? [.claudeCode] : detected
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

    private func updateSelection(afterLoading skills: [SkillsHubSkill]) {
        if let selectedSkillID,
           skills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        selectedSkillID = skills.first?.id
    }
}
