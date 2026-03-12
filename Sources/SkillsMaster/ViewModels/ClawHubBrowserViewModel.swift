import Foundation
import Observation

/// ViewModel for ClawHub marketplace browsing and install flow.
@MainActor
@Observable
final class ClawHubBrowserViewModel {

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var searchText = ""
    var selectedSort: ClawHubService.SkillSort = .default
    var selectedDirection: ClawHubService.SortDirection = .descending
    var highlightedOnly = false
    var nonSuspiciousOnly = false

    var displayedSkills: [ClawHubSkill] = []
    var isLoading = false
    var errorMessage: String?

    var selectedSkillID: String?
    var selectedSkillDetail: ClawHubSkillDetail?
    var fetchedContent: SkillMDParser.ParseResult?
    var isLoadingDetail = false
    var isLoadingContent = false
    var detailError: String?
    var contentError: String?

    var installingSkillSlug: String?
    var notice: Notice?

    var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedSkill: ClawHubSkill? {
        guard let selectedSkillID else { return nil }
        return displayedSkills.first { $0.id == selectedSkillID }
    }

    private let service: ClawHubService
    private let skillManager: SkillManager
    private var installedClawHubSlugs = Set<String>()
    private var installedSkillIDsNoSource = Set<String>()
    private var hasLoadedInitialSkills = false
    private var searchTask: Task<Void, Never>?
    private var currentDetailSlug: String?

    init(skillManager: SkillManager, service: ClawHubService = ClawHubService()) {
        self.skillManager = skillManager
        self.service = service
    }

    // MARK: - Lifecycle / list loading

    func onAppear() async {
        syncInstalledSkills()
        guard !hasLoadedInitialSkills else { return }
        hasLoadedInitialSkills = true
        await loadFeaturedSkills()
    }

    func refresh() async {
        syncInstalledSkills()
        if isSearchActive {
            await performSearch(query: searchText)
        } else {
            await loadFeaturedSkills()
        }
    }

    func onSearchTextChanged() {
        searchTask?.cancel()

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            Task { await loadFeaturedSkills() }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmedQuery)
        }
    }

    func selectSort(_ sort: ClawHubService.SkillSort) {
        guard selectedSort != sort else { return }
        selectedSort = sort
        reloadBrowseListIfNeeded()
    }

    func selectDirection(_ direction: ClawHubService.SortDirection) {
        guard selectedDirection != direction else { return }
        selectedDirection = direction
        reloadBrowseListIfNeeded()
    }

    func toggleHighlightedOnly() {
        highlightedOnly.toggle()
        reloadBrowseListIfNeeded()
    }

    func toggleNonSuspiciousOnly() {
        nonSuspiciousOnly.toggle()
        reloadBrowseListIfNeeded()
    }

    func syncInstalledSkills() {
        installedClawHubSlugs = Set(
            skillManager.skills.compactMap { skill in
                guard skill.lockEntry?.sourceType == "clawhub" else { return nil }
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

    func isInstalled(_ skill: ClawHubSkill) -> Bool {
        if installedClawHubSlugs.contains(skill.slug) {
            return true
        }
        return installedSkillIDsNoSource.contains(skill.slug)
    }

    func isInstalling(_ skill: ClawHubSkill) -> Bool {
        installingSkillSlug == skill.slug
    }

    // MARK: - Detail loading

    func loadSelection(for skill: ClawHubSkill) async {
        currentDetailSlug = skill.slug
        selectedSkillDetail = nil
        fetchedContent = nil
        detailError = nil
        contentError = nil
        isLoadingDetail = true
        isLoadingContent = true

        let targetSlug = skill.slug

        do {
            let detail = try await service.fetchSkillDetail(slug: targetSlug)
            guard currentDetailSlug == targetSlug else { return }
            selectedSkillDetail = detail
        } catch {
            guard currentDetailSlug == targetSlug else { return }
            detailError = error.localizedDescription
        }
        isLoadingDetail = false

        do {
            let rawContent = try await service.fetchSkillContent(slug: targetSlug)
            guard currentDetailSlug == targetSlug else { return }

            do {
                fetchedContent = try SkillMDParser.parse(content: rawContent)
            } catch {
                fetchedContent = SkillMDParser.ParseResult(
                    metadata: SkillMetadata(name: skill.name, description: skill.descriptionText),
                    markdownBody: rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } catch {
            guard currentDetailSlug == targetSlug else { return }
            contentError = error.localizedDescription
        }
        isLoadingContent = false
    }

    // MARK: - Installation

    func installSkill(_ skill: ClawHubSkill) {
        guard installingSkillSlug == nil else { return }
        Task { await performInstall(skill) }
    }

    private func performInstall(_ skill: ClawHubSkill) async {
        installingSkillSlug = skill.slug
        defer { installingSkillSlug = nil }

        do {
            let detail = try await service.fetchSkillDetail(slug: skill.slug)
            guard let version = detail.installVersion else {
                throw SkillManager.ImportError.parseFailed("ClawHub did not provide a version for \(skill.slug).")
            }

            var archiveData: Data?
            var archiveDownloadError: Error?
            do {
                archiveData = try await service.downloadSkillArchive(slug: skill.slug, version: version)
            } catch {
                archiveDownloadError = error
            }

            var skillContent: String?
            var skillContentError: Error?
            do {
                skillContent = try await service.fetchSkillContent(slug: skill.slug)
            } catch {
                skillContentError = error
            }

            if archiveData == nil && skillContent == nil {
                throw archiveDownloadError ?? skillContentError ?? ClawHubService.ServiceError.archiveUnavailable
            }

            let result = try await skillManager.installClawHubSkill(
                slug: skill.slug,
                version: version,
                detailPageURL: skill.browserURL.absoluteString,
                skillContent: skillContent,
                archiveData: archiveData,
                targetAgents: [.openClaw]
            )

            syncInstalledSkills()

            if result == .installedSkillMarkdownOnly {
                let reason = archiveDownloadError?.localizedDescription ??
                    "ClawHub did not return a downloadable archive for this skill version."
                notice = Notice(
                    title: "Installed with limited files",
                    message: "SkillsMaster installed SKILL.md for OpenClaw, but auxiliary files were not included. Reason: \(reason)"
                )
            } else {
                notice = Notice(
                    title: "Installed",
                    message: "\(skill.name) is now available to OpenClaw."
                )
            }
        } catch {
            notice = Notice(title: "Installation Failed", message: error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func loadFeaturedSkills() async {
        isLoading = true
        errorMessage = nil

        do {
            let skills = try await service.fetchSkills(options: browseOptions)
            displayedSkills = skills
            updateSelection(afterLoading: skills)
        } catch {
            displayedSkills = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func performSearch(query: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let skills = try await service.searchSkills(query: query)
            displayedSkills = skills
            selectedSkillID = skills.first?.id
        } catch {
            displayedSkills = []
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private var browseOptions: ClawHubService.BrowseOptions {
        ClawHubService.BrowseOptions(
            sort: selectedSort,
            direction: selectedDirection,
            highlightedOnly: highlightedOnly,
            nonSuspiciousOnly: nonSuspiciousOnly
        )
    }

    private func reloadBrowseListIfNeeded() {
        guard !isSearchActive else { return }
        Task { await loadFeaturedSkills() }
    }

    private func updateSelection(afterLoading skills: [ClawHubSkill]) {
        if let selectedSkillID, skills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        selectedSkillID = skills.first?.id
    }
}
