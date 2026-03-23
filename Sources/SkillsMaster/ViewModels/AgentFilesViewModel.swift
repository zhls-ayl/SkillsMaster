import Foundation
import AppKit
import Combine

@MainActor
@Observable
final class AgentFilesViewModel {

    let agentType: AgentType
    let rootURL: URL
    let protectedURL: URL

    var entries: [AgentFileItem] = []
    var selectedItemID: String?
    var expandedDirectoryIDs = Set<String>()
    var isLoading = false
    var rootExists = false
    var errorMessage: String?
    var selectedItemDetails: AgentFileDetails?
    var isLoadingSelectedItemDetails = false

    @ObservationIgnored private let service: AgentFileBrowserService
    @ObservationIgnored private let watcher = FileSystemWatcher()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var childrenByParentID: [String: [AgentFileItem]] = [:]
    @ObservationIgnored private var loadingDirectoryIDs = Set<String>()
    @ObservationIgnored private var watchBaseURL: URL
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var directoryLoadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var detailsTask: Task<Void, Never>?

    init(
        agentType: AgentType,
        service: AgentFileBrowserService = AgentFileBrowserService()
    ) {
        self.agentType = agentType
        self.rootURL = agentType.configDirectoryURL ?? agentType.skillsDirectoryURL.deletingLastPathComponent()
        self.protectedURL = agentType.skillsDirectoryURL
        self.watchBaseURL = self.rootURL
        self.service = service
        setupWatcher()
    }

    deinit {
        reloadTask?.cancel()
        detailsTask?.cancel()
        directoryLoadTasks.values.forEach { $0.cancel() }
    }

    var title: String {
        "\(agentType.displayName) Files"
    }

    var rootDisplayPath: String {
        rootURL.path
    }

    var selectedItem: AgentFileItem? {
        guard let selectedItemID else { return nil }
        return findItem(withID: selectedItemID, in: entries)
    }

    var selectedOrRootPath: URL {
        selectedItem?.url ?? rootURL
    }

    var canCreateInCurrentDirectory: Bool {
        service.canCreateChild(in: currentCreationDirectoryURL, protectedURL: protectedURL)
    }

    var canRenameSelectedItem: Bool {
        guard let selectedItem else { return false }
        return service.canMutateItem(at: selectedItem.url, rootURL: rootURL, protectedURL: protectedURL)
    }

    var canDeleteSelectedItem: Bool {
        guard let selectedItem else { return false }
        return service.canMutateItem(at: selectedItem.url, rootURL: rootURL, protectedURL: protectedURL)
    }

    var canOpenSelectedTextFile: Bool {
        guard let selectedItem else { return false }
        return !selectedItem.isProtected && selectedItemDetails?.isTextFile == true
    }

    var canRevealSelectedOrRoot: Bool {
        pathExists(selectedOrRootPath)
    }

    var canOpenSelectedOrRootInTerminal: Bool {
        let terminalURL = terminalTargetURL(for: selectedItem?.url ?? rootURL)
        return pathExists(terminalURL)
    }

    var currentCreationDirectoryURL: URL {
        guard let selectedItem else { return rootURL }

        if selectedItem.isExpandable {
            return selectedItem.url
        }

        return selectedItem.url.deletingLastPathComponent()
    }

    func reloadIfNeeded() {
        guard !hasLoadedOnce else { return }
        reload()
    }

    func reload() {
        reloadTask?.cancel()
        detailsTask?.cancel()
        directoryLoadTasks.values.forEach { $0.cancel() }
        directoryLoadTasks = [:]
        loadingDirectoryIDs = []
        isLoading = true
        errorMessage = nil

        let expandedIDsToRestore = expandedDirectoryIDs

        reloadTask = Task { [service, agentType] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try service.loadRootSnapshot(for: agentType)
                }.value
                guard !Task.isCancelled else { return }

                entries = snapshot.entries
                rootExists = snapshot.rootExists
                watchBaseURL = snapshot.watchBaseURL
                childrenByParentID = [:]
                expandedDirectoryIDs = []
                selectedItemDetails = nil
                hasLoadedOnce = true

                if snapshot.rootExists {
                    await restoreExpandedDirectories(expandedIDsToRestore)
                }

                normalizeSelection()
                restartWatcher()
                isLoading = false
                loadSelectedItemDetails()
            } catch {
                guard !Task.isCancelled else { return }
                entries = []
                rootExists = false
                childrenByParentID = [:]
                expandedDirectoryIDs = []
                selectedItemDetails = nil
                watchBaseURL = nearestExistingAncestor(for: rootURL)
                restartWatcher()
                errorMessage = error.localizedDescription
                hasLoadedOnce = true
                isLoading = false
            }
        }
    }

    func toggleExpansion(for item: AgentFileItem) {
        guard item.isExpandable else { return }

        if expandedDirectoryIDs.contains(item.id) {
            expandedDirectoryIDs.remove(item.id)
            restartWatcher()
            return
        }

        expandedDirectoryIDs.insert(item.id)
        restartWatcher()

        guard childrenByParentID[item.id] == nil else { return }
        loadChildren(for: item)
    }

    func isExpanded(_ item: AgentFileItem) -> Bool {
        expandedDirectoryIDs.contains(item.id)
    }

    func isLoadingChildren(for item: AgentFileItem) -> Bool {
        loadingDirectoryIDs.contains(item.id)
    }

    func children(for item: AgentFileItem) -> [AgentFileItem] {
        childrenByParentID[item.id] ?? []
    }

    func loadedChildCount(for item: AgentFileItem) -> Int? {
        findItem(withID: item.id, in: entries)?.loadedChildCount
    }

    func loadSelectedItemDetails() {
        detailsTask?.cancel()
        selectedItemDetails = nil
        isLoadingSelectedItemDetails = false

        guard let selectedItem else { return }
        guard !selectedItem.isDirectory, !selectedItem.isSymbolicLink else { return }

        detailsTask = Task { [service] in
            isLoadingSelectedItemDetails = true

            do {
                let details = try await Task.detached(priority: .utility) {
                    try service.loadItemDetails(at: selectedItem.url)
                }.value

                guard !Task.isCancelled else { return }
                selectedItemDetails = details
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            if !Task.isCancelled {
                isLoadingSelectedItemDetails = false
            }
        }
    }

    func createFile(named name: String, replaceExisting: Bool = false) throws {
        let newURL = try service.createItem(
            named: name,
            kind: .file,
            in: currentCreationDirectoryURL,
            rootURL: rootURL,
            protectedURL: protectedURL,
            replaceExisting: replaceExisting
        )

        reload()
        selectedItemID = newURL.standardizedFileURL.path
    }

    func createFolder(named name: String, replaceExisting: Bool = false) throws {
        let newURL = try service.createItem(
            named: name,
            kind: .folder,
            in: currentCreationDirectoryURL,
            rootURL: rootURL,
            protectedURL: protectedURL,
            replaceExisting: replaceExisting
        )

        reload()
        selectedItemID = newURL.standardizedFileURL.path
    }

    func renameSelectedItem(to name: String, replaceExisting: Bool = false) throws {
        guard let selectedItem else { return }

        let newURL = try service.renameItem(
            at: selectedItem.url,
            to: name,
            rootURL: rootURL,
            protectedURL: protectedURL,
            replaceExisting: replaceExisting
        )

        selectedItemID = newURL.standardizedFileURL.path
        reload()
    }

    func deleteSelectedItem() throws {
        guard let selectedItem else { return }
        let parentID = selectedItem.url.deletingLastPathComponent().standardizedFileURL.path

        try service.deleteItem(at: selectedItem.url, rootURL: rootURL, protectedURL: protectedURL)

        selectedItemID = parentID == rootURL.standardizedFileURL.path ? nil : parentID
        reload()
    }

    func revealSelectedOrRootInFinder() {
        let targetURL = selectedItem?.url ?? rootURL

        if pathExists(targetURL) {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL.deletingLastPathComponent()])
        }
    }

    func openSelectedOrRootInTerminal() {
        let targetURL = terminalTargetURL(for: selectedItem?.url ?? rootURL)
        guard pathExists(targetURL) else { return }

        let escapedPath = targetURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            do script "cd '\(escapedPath)'"
            activate
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                errorMessage = error.description
            }
        }
    }

    func openSelectedFileInDefaultApp() {
        guard let selectedItem, canOpenSelectedTextFile else { return }

        guard NSWorkspace.shared.open(selectedItem.url) else {
            errorMessage = "无法用系统默认应用打开该文件。"
            return
        }
    }

    private func loadChildren(for item: AgentFileItem) {
        directoryLoadTasks[item.id]?.cancel()
        loadingDirectoryIDs.insert(item.id)

        directoryLoadTasks[item.id] = Task { [service, rootURL, protectedURL] in
            do {
                let children = try await Task.detached(priority: .userInitiated) {
                    try service.loadDirectoryContents(
                        at: item.url,
                        rootURL: rootURL,
                        protectedURL: protectedURL
                    )
                }.value

                guard !Task.isCancelled else { return }

                childrenByParentID[item.id] = children
                updateLoadedChildCount(children.count, forItemID: item.id)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            if !Task.isCancelled {
                loadingDirectoryIDs.remove(item.id)
                directoryLoadTasks[item.id] = nil
                normalizeSelection()
            }
        }
    }

    private func restoreExpandedDirectories(_ ids: Set<String>) async {
        let sortedIDs = ids.sorted { lhs, rhs in
            lhs.split(separator: "/").count < rhs.split(separator: "/").count
        }

        for id in sortedIDs {
            guard let item = findItem(withID: id, in: entries), item.isExpandable else { continue }

            expandedDirectoryIDs.insert(id)

            if childrenByParentID[id] == nil {
                do {
                    let service = self.service
                    let rootURL = self.rootURL
                    let protectedURL = self.protectedURL

                    let children = try await Task.detached(priority: .utility) {
                        try service.loadDirectoryContents(
                            at: item.url,
                            rootURL: rootURL,
                            protectedURL: protectedURL
                        )
                    }.value

                    guard !Task.isCancelled else { return }

                    childrenByParentID[id] = children
                    updateLoadedChildCount(children.count, forItemID: id)
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func setupWatcher() {
        watcher.onChange
            .sink { [weak self] in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    private func restartWatcher() {
        var paths = Set<URL>()
        paths.insert(rootExists ? rootURL.standardizedFileURL : watchBaseURL.standardizedFileURL)

        for directoryID in expandedDirectoryIDs {
            if let item = findItem(withID: directoryID, in: entries), item.isExpandable {
                paths.insert(item.url.standardizedFileURL)
            }
        }

        watcher.startWatching(paths: paths.sorted { $0.path < $1.path })
    }

    private func normalizeSelection() {
        guard let selectedItemID else { return }
        if findItem(withID: selectedItemID, in: entries) == nil {
            self.selectedItemID = nil
        }
    }

    private func findItem(withID id: String, in items: [AgentFileItem]) -> AgentFileItem? {
        for item in items {
            if item.id == id {
                return item
            }

            if let children = childrenByParentID[item.id], let found = findItem(withID: id, in: children) {
                return found
            }
        }
        return nil
    }

    private func updateLoadedChildCount(_ count: Int, forItemID itemID: String) {
        if let index = entries.firstIndex(where: { $0.id == itemID }) {
            entries[index].loadedChildCount = count
            return
        }

        for parentID in childrenByParentID.keys {
            if let index = childrenByParentID[parentID]?.firstIndex(where: { $0.id == itemID }) {
                childrenByParentID[parentID]?[index].loadedChildCount = count
                return
            }
        }
    }

    private func terminalTargetURL(for url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        if let selectedItem, selectedItem.url.standardizedFileURL.path == standardizedURL.path, !selectedItem.isDirectory {
            return standardizedURL.deletingLastPathComponent()
        }
        return standardizedURL
    }

    private func pathExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || SymlinkManager.isSymlink(at: url)
    }

    private func nearestExistingAncestor(for url: URL) -> URL {
        var candidate = url.standardizedFileURL
        let fm = FileManager.default

        while !fm.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }

        return candidate
    }
}
