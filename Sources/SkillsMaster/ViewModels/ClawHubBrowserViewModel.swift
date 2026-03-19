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
    var selectedSort: ClawHubService.SkillSort = .downloads
    var selectedDirection: ClawHubService.SortDirection = .descending
    var highlightedOnly = false
    var nonSuspiciousOnly = false

    var displayedSkills: [ClawHubSkill] = []
    var isLoading = false
    var errorMessage: String?

    var isLoadingMore = false
    var loadMoreErrorMessage: String?
    private(set) var hasMoreResults = true

    var selectedSkillID: String?
    var selectedSkillDetail: ClawHubSkillDetail?
    var fetchedContent: SkillMDParser.ParseResult?
    var isLoadingDetail = false
    var isLoadingContent = false
    var detailError: String?
    var contentError: String?

    var installingSkillSlug: String?
    var installingStatusMessage: String?
    var notice: Notice?

    var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedSkill: ClawHubSkill? {
        guard let selectedSkillID else { return nil }
        return displayedSkills.first { $0.id == selectedSkillID }
    }

    private let service: any ClawHubServiceProtocol
    private let skillManager: SkillManager
    private var installedClawHubSlugs = Set<String>()
    private var installedSkillIDsNoSource = Set<String>()
    private var hasLoadedInitialSkills = false
    private var searchTask: Task<Void, Never>?
    private var currentDetailSlug: String?
    private let pageSize = 50
    private let loadMoreThreshold = 5
    private var nextBrowseCursor: String?
    private var currentSearchLimit = 50
    private var listRequestVersion = 0

    init(skillManager: SkillManager, service: any ClawHubServiceProtocol = ClawHubService()) {
        self.skillManager = skillManager
        self.service = service
    }

    // MARK: - Lifecycle / list loading

    func onAppear() async {
        syncInstalledSkills()
        guard !hasLoadedInitialSkills else { return }
        hasLoadedInitialSkills = true
        await reloadCurrentList()
    }

    func refresh() async {
        syncInstalledSkills()
        await reloadCurrentList()
    }

    func onSearchTextChanged() {
        searchTask?.cancel()

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            Task { await reloadCurrentList() }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await reloadCurrentList()
        }
    }

    func loadMoreIfNeeded(after skillID: String) async {
        guard shouldLoadMore(after: skillID) else { return }
        await loadMore()
    }

    func retryLoadMore() async {
        guard !isLoading else { return }
        await loadMore()
    }

    func selectSort(_ sort: ClawHubService.SkillSort) {
        guard selectedSort != sort else { return }
        selectedSort = sort
        selectedDirection = sort.defaultDirection
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

    func canReinstall(_ skill: ClawHubSkill) -> Bool {
        installedClawHubSlugs.contains(skill.slug)
    }

    func isInstalling(_ skill: ClawHubSkill) -> Bool {
        installingSkillSlug == skill.slug
    }

    func installButtonTitle(for skill: ClawHubSkill) -> String {
        if isInstalling(skill) {
            return installingStatusMessage ?? "Installing..."
        }
        if canReinstall(skill) {
            return "Reinstall"
        }
        return "Install"
    }

    func detailInstallButtonTitle(for skill: ClawHubSkill) -> String {
        if isInstalling(skill) {
            return installingStatusMessage ?? "Installing..."
        }
        if canReinstall(skill) {
            return "Reinstall to OpenClaw"
        }
        return "Install to OpenClaw"
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
        installingStatusMessage = "Loading package info..."
        defer {
            installingSkillSlug = nil
            installingStatusMessage = nil
        }

        do {
            installingStatusMessage = "Loading package info..."
            let detail = try await service.fetchSkillDetail(slug: skill.slug)
            guard let version = detail.installVersion else {
                throw SkillManager.ImportError.parseFailed("ClawHub did not provide a version for \(skill.slug).")
            }

            installingStatusMessage = "Downloading archive..."
            let archiveResult = await downloadArchiveForInstall(slug: skill.slug, version: version)
            let archiveData = archiveResult.data
            let archiveDownloadError = archiveResult.error

            var skillContent: String?
            var skillContentError: Error?
            do {
                installingStatusMessage = "Fetching SKILL.md..."
                skillContent = try await service.fetchSkillContent(slug: skill.slug)
            } catch {
                skillContentError = error
            }

            if archiveData == nil && skillContent == nil {
                throw archiveDownloadError ?? skillContentError ?? ClawHubService.ServiceError.archiveUnavailable
            }

            installingStatusMessage = archiveData == nil
                ? "Installing SKILL.md..."
                : "Installing files..."
            let result = try await skillManager.installClawHubSkill(
                slug: skill.slug,
                version: version,
                detailPageURL: detail.skill.browserURL.absoluteString,
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

    private var browseOptions: ClawHubService.BrowseOptions {
        ClawHubService.BrowseOptions(
            sort: selectedSort,
            direction: selectedDirection,
            highlightedOnly: highlightedOnly,
            nonSuspiciousOnly: nonSuspiciousOnly,
            limit: pageSize,
            cursor: nextBrowseCursor
        )
    }

    private func reloadBrowseListIfNeeded() {
        guard !isSearchActive else { return }
        Task { await reloadCurrentList() }
    }

    private func updateSelection(afterLoading skills: [ClawHubSkill]) {
        if let selectedSkillID, skills.contains(where: { $0.id == selectedSkillID }) {
            return
        }
        selectedSkillID = skills.first?.id
    }

    private func reloadCurrentList() async {
        nextBrowseCursor = nil
        currentSearchLimit = pageSize
        hasMoreResults = true
        isLoadingMore = false
        loadMoreErrorMessage = nil
        await fetchCurrentList(reset: true)
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMoreResults else { return }

        if normalizedQuery != nil {
            currentSearchLimit += pageSize
        } else if nextBrowseCursor == nil {
            hasMoreResults = false
            return
        }

        await fetchCurrentList(reset: false)
    }

    private func fetchCurrentList(reset: Bool) async {
        listRequestVersion += 1
        let requestVersion = listRequestVersion

        if reset {
            isLoading = true
            errorMessage = nil
        } else {
            isLoadingMore = true
            loadMoreErrorMessage = nil
        }

        do {
            let skills: [ClawHubSkill]
            var loadedNextBrowseCursor: String?
            var loadedHasMoreResults = false
            if let query = normalizedQuery {
                skills = try await service.searchSkills(query: query, limit: currentSearchLimit)
            } else {
                let page = try await service.fetchSkills(options: browseOptions)
                loadedNextBrowseCursor = page.nextCursor
                loadedHasMoreResults = page.hasMore && page.nextCursor != nil
                skills = reset
                    ? page.items
                    : mergeSkills(existing: displayedSkills, new: page.items)
            }

            guard requestVersion == listRequestVersion else { return }

            if normalizedQuery == nil {
                nextBrowseCursor = loadedNextBrowseCursor
                hasMoreResults = loadedHasMoreResults
            }
            displayedSkills = skills
            if normalizedQuery != nil {
                hasMoreResults = !skills.isEmpty && skills.count >= currentSearchLimit
            }
            updateSelection(afterLoading: skills)
        } catch {
            guard requestVersion == listRequestVersion else { return }

            if reset {
                displayedSkills = []
                errorMessage = error.localizedDescription
            } else {
                if normalizedQuery != nil {
                    currentSearchLimit = max(pageSize, currentSearchLimit - pageSize)
                }
                loadMoreErrorMessage = error.localizedDescription
            }
        }

        guard requestVersion == listRequestVersion else { return }
        if reset {
            isLoading = false
        } else {
            isLoadingMore = false
        }
    }

    private var normalizedQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldLoadMore(after skillID: String) -> Bool {
        guard hasMoreResults, !isLoading, !isLoadingMore, loadMoreErrorMessage == nil else {
            return false
        }
        guard let index = displayedSkills.firstIndex(where: { $0.id == skillID }) else {
            return false
        }
        let triggerIndex = max(displayedSkills.count - loadMoreThreshold, 0)
        return index >= triggerIndex
    }

    private func mergeSkills(existing: [ClawHubSkill], new: [ClawHubSkill]) -> [ClawHubSkill] {
        var merged = existing
        let existingIDs = Set(existing.map(\.id))
        merged.append(contentsOf: new.filter { !existingIDs.contains($0.id) })
        return merged
    }

    private func downloadArchiveForInstall(slug: String, version: String) async -> (data: Data?, error: Error?) {
        var lastError: Error?

        for attempt in 0..<2 {
            do {
                let data = try await service.downloadSkillArchive(slug: slug, version: version)
                return (data, nil)
            } catch let error as ClawHubService.ServiceError {
                lastError = error

                guard case .rateLimited(let retryAfterSeconds) = error,
                      attempt == 0,
                      let retryAfterSeconds,
                      retryAfterSeconds > 0,
                      retryAfterSeconds <= 60 else {
                    break
                }

                for remaining in stride(from: retryAfterSeconds, through: 1, by: -1) {
                    installingStatusMessage = "Waiting for ClawHub rate limit (\(remaining)s)..."
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                installingStatusMessage = "Retrying archive download..."
            } catch {
                lastError = error
                break
            }
        }

        return (nil, lastError)
    }
}
