import Foundation
import Combine

@MainActor
@Observable
final class SkillRelatedFilesViewModel {

    enum PendingNavigationAction {
        case closeEditor
        case home
        case item(String)
    }

    let skillRootURL: URL
    let toolPreferences: ToolPreferencesStore

    var isLoading = false
    var errorMessage: String?
    var isDrawerPresented = false
    var nodes: [SkillRelatedFileNode] = []
    var extraItemCount = 0
    var hasNestedDirectories = false
    var searchQuery = ""
    var selectedItemID: String?
    var expandedDirectoryIDs = Set<String>()
    var selectedItemDetails: AgentFileDetails?
    var isLoadingSelectedItemDetails = false
    var previewViewModel: TextFilePreviewViewModel?
    var editorViewModel: TextFileEditorViewModel?
    var pendingNavigationAction: PendingNavigationAction?
    var missingSelectionPath: String?
    var externalChangeMessage: String?

    @ObservationIgnored private let service: SkillFileBrowserService
    @ObservationIgnored private let watcher = FileSystemWatcher()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var watchPaths: [URL] = []

    init(
        skillRootURL: URL,
        toolPreferences: ToolPreferencesStore,
        service: SkillFileBrowserService = SkillFileBrowserService()
    ) {
        self.skillRootURL = skillRootURL.standardizedFileURL
        self.toolPreferences = toolPreferences
        self.service = service
        setupWatcher()
    }

    deinit {
        reloadTask?.cancel()
        detailsTask?.cancel()
        watcher.stopWatching()
    }

    var hasRelatedFiles: Bool {
        extraItemCount > 0
    }

    var hasCompletedInitialLoad: Bool {
        hasLoadedOnce
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowSearch: Bool {
        extraItemCount > 12 || hasNestedDirectories
    }

    var hasUnsavedChangesInEditor: Bool {
        editorViewModel?.hasUnsavedChanges == true
    }

    var selectedItem: AgentFileItem? {
        guard let selectedItemID else { return nil }
        return findItem(withID: selectedItemID, in: nodes)
    }

    var filteredNodes: [SkillRelatedFileNode] {
        filterNodes(nodes, query: searchQuery)
    }

    var isShowingSupplementalContent: Bool {
        editorViewModel != nil || selectedItem != nil || missingSelectionPath != nil
    }

    var isShowingHomeContent: Bool {
        !isShowingSupplementalContent
    }

    var canEditSelectedFile: Bool {
        guard let selectedItem else { return false }
        return !selectedItem.isDirectory
            && !selectedItem.isSymbolicLink
            && (TextEditableFileKind.from(url: selectedItem.url) != nil
                || selectedItemDetails?.isTextFile == true)
    }

    var canOpenSelectedInExternalEditor: Bool {
        selectedItem != nil
    }

    var currentSelectedDisplayName: String {
        if let selectedItem {
            return selectedItem.name
        }
        if let missingSelectionPath {
            return URL(fileURLWithPath: missingSelectionPath).lastPathComponent
        }
        return "SKILL.md"
    }

    var currentRelativePath: String {
        if let selectedItem {
            return selectedItem.relativePath
        }
        if let missingSelectionPath {
            return relativePath(for: URL(fileURLWithPath: missingSelectionPath))
        }
        return "SKILL.md"
    }

    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        reload()
    }

    func reload() {
        reloadTask?.cancel()
        detailsTask?.cancel()

        if editorViewModel != nil {
            externalChangeMessage = appLocalized("Files changed outside the editor. Save or discard your changes before reloading.")
            return
        }

        let previousSelectionPath = selectedItem?.url.standardizedFileURL.path ?? missingSelectionPath
        isLoading = true
        errorMessage = nil
        externalChangeMessage = nil

        reloadTask = Task { [service, skillRootURL] in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try service.loadSnapshot(rootURL: skillRootURL)
                }.value
                guard !Task.isCancelled else { return }

                nodes = snapshot.nodes
                extraItemCount = snapshot.extraItemCount
                hasNestedDirectories = snapshot.hasNestedDirectories
                watchPaths = snapshot.watchPaths
                expandedDirectoryIDs = expandedDirectoryIDs.intersection(directoryIDs(in: snapshot.nodes))
                hasLoadedOnce = true

                if !snapshot.watchPaths.isEmpty {
                    watcher.startWatching(paths: snapshot.watchPaths)
                }

                if let previousSelectionPath,
                   findItem(withID: previousSelectionPath, in: snapshot.nodes) != nil {
                    selectedItemID = previousSelectionPath
                    missingSelectionPath = nil
                } else if let previousSelectionPath {
                    selectedItemID = nil
                    missingSelectionPath = previousSelectionPath
                } else {
                    selectedItemID = nil
                    missingSelectionPath = nil
                }

                if !hasRelatedFiles {
                    isDrawerPresented = false
                }

                prepareSelectedItemPreview()
                loadSelectedItemDetails()
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                hasLoadedOnce = true
                isLoading = false
            }
        }
    }

    func toggleDrawer() {
        guard hasRelatedFiles else { return }
        isDrawerPresented.toggle()
    }

    func requestHomeSelection() {
        guard selectedItemID != nil || missingSelectionPath != nil || editorViewModel != nil else { return }

        if hasUnsavedChangesInEditor {
            pendingNavigationAction = .home
            return
        }

        closeEditor()
        selectedItemID = nil
        missingSelectionPath = nil
        previewViewModel = nil
        selectedItemDetails = nil
        isLoadingSelectedItemDetails = false
    }

    func requestSelectionChange(to itemID: String) {
        guard selectedItemID != itemID || missingSelectionPath != nil else { return }

        if hasUnsavedChangesInEditor {
            pendingNavigationAction = .item(itemID)
            return
        }

        closeEditor()
        selectedItemID = itemID
        missingSelectionPath = nil
        externalChangeMessage = nil
        prepareSelectedItemPreview()
        loadSelectedItemDetails()
    }

    func toggleExpansion(for node: SkillRelatedFileNode) {
        guard node.item.isExpandable else { return }
        if expandedDirectoryIDs.contains(node.id) {
            expandedDirectoryIDs.remove(node.id)
        } else {
            expandedDirectoryIDs.insert(node.id)
        }
    }

    func isExpanded(_ node: SkillRelatedFileNode) -> Bool {
        isSearching || expandedDirectoryIDs.contains(node.id)
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
                prepareSelectedItemPreview()
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            if !Task.isCancelled {
                isLoadingSelectedItemDetails = false
            }
        }
    }

    func revealSelectedOrRootInFinder() {
        let targetURL = selectedItem?.url ?? skillRootURL
        ApplicationLauncher.revealInFinder(itemURL: targetURL)
    }

    func openSelectedOrRootInTerminal() {
        let targetURL = terminalTargetURL(for: selectedItem?.url ?? skillRootURL)

        do {
            try ApplicationLauncher.openInTerminal(
                directoryURL: targetURL,
                preferences: toolPreferences
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSelectedInExternalEditor() {
        guard let selectedItem else { return }

        do {
            try ApplicationLauncher.openInExternalEditor(
                itemURL: selectedItem.url,
                preferences: toolPreferences
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startEditingSelectedFile() {
        guard let selectedItem, canEditSelectedFile else { return }
        errorMessage = nil
        previewViewModel = nil
        editorViewModel = TextFileEditorViewModel(fileURL: selectedItem.url)
        selectedItemDetails = nil
        externalChangeMessage = nil
    }

    func requestCloseEditor() {
        guard let editorViewModel else { return }
        if editorViewModel.hasUnsavedChanges {
            pendingNavigationAction = .closeEditor
            return
        }
        closeEditor()
        prepareSelectedItemPreview()
        loadSelectedItemDetails()
    }

    func cancelPendingNavigationAction() {
        pendingNavigationAction = nil
    }

    func discardPendingNavigationAction() {
        let pendingAction = pendingNavigationAction
        pendingNavigationAction = nil
        closeEditor()

        switch pendingAction {
        case .closeEditor:
            prepareSelectedItemPreview()
            loadSelectedItemDetails()
        case .home:
            selectedItemID = nil
            missingSelectionPath = nil
            previewViewModel = nil
            selectedItemDetails = nil
            isLoadingSelectedItemDetails = false
        case .item(let itemID):
            selectedItemID = itemID
            missingSelectionPath = nil
            prepareSelectedItemPreview()
            loadSelectedItemDetails()
        case nil:
            break
        }
    }

    func saveCurrentEditorAndClose() async -> Bool {
        guard let editorViewModel else { return false }
        let didSave = await editorViewModel.save()
        guard didSave else { return false }

        closeEditor()
        reload()
        return true
    }

    func savePendingNavigationAction() async -> Bool {
        guard let editorViewModel else { return false }
        let pendingAction = pendingNavigationAction
        let didSave = await editorViewModel.save()
        guard didSave else { return false }

        closeEditor()
        pendingNavigationAction = nil

        switch pendingAction {
        case .closeEditor:
            reload()
        case .home:
            selectedItemID = nil
            missingSelectionPath = nil
            reload()
        case .item(let itemID):
            selectedItemID = itemID
            missingSelectionPath = nil
            reload()
        case nil:
            reload()
        }

        return true
    }

    private func setupWatcher() {
        watcher.onChange
            .sink { [weak self] in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    private func prepareSelectedItemPreview() {
        guard let selectedItem,
              !selectedItem.isDirectory,
              !selectedItem.isSymbolicLink,
              (TextEditableFileKind.from(url: selectedItem.url) != nil
                || selectedItemDetails?.isTextFile == true) else {
            previewViewModel = nil
            return
        }

        previewViewModel = TextFilePreviewViewModel(fileURL: selectedItem.url)
    }

    private func terminalTargetURL(for url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        if let selectedItem,
           selectedItem.url.standardizedFileURL.path == standardizedURL.path,
           !selectedItem.isDirectory {
            return standardizedURL.deletingLastPathComponent()
        }
        return standardizedURL
    }

    private func closeEditor() {
        editorViewModel = nil
        pendingNavigationAction = nil
        externalChangeMessage = nil
    }

    private func findItem(withID id: String, in nodes: [SkillRelatedFileNode]) -> AgentFileItem? {
        for node in nodes {
            if node.id == id {
                return node.item
            }

            if let found = findItem(withID: id, in: node.children) {
                return found
            }
        }
        return nil
    }

    private func filterNodes(
        _ nodes: [SkillRelatedFileNode],
        query rawQuery: String
    ) -> [SkillRelatedFileNode] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes }

        return nodes.compactMap { node in
            let filteredChildren = filterNodes(node.children, query: query)
            let matches = node.item.name.localizedCaseInsensitiveContains(query)
                || node.item.relativePath.localizedCaseInsensitiveContains(query)

            guard matches || !filteredChildren.isEmpty else { return nil }
            return SkillRelatedFileNode(item: node.item, children: filteredChildren)
        }
    }

    private func directoryIDs(in nodes: [SkillRelatedFileNode]) -> Set<String> {
        var ids = Set<String>()

        for node in nodes where node.item.isDirectory {
            ids.insert(node.id)
            ids.formUnion(directoryIDs(in: node.children))
        }

        return ids
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = skillRootURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath) else { return url.lastPathComponent }

        let relative = String(itemPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }
}
