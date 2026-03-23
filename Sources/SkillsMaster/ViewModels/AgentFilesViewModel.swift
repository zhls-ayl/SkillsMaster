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
    var isLoading = false
    var rootExists = false
    var errorMessage: String?

    @ObservationIgnored private let service: AgentFileBrowserService
    @ObservationIgnored private let watcher = FileSystemWatcher()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var hasLoadedOnce = false

    init(
        agentType: AgentType,
        service: AgentFileBrowserService = AgentFileBrowserService()
    ) {
        self.agentType = agentType
        self.rootURL = agentType.configDirectoryURL ?? agentType.skillsDirectoryURL.deletingLastPathComponent()
        self.protectedURL = agentType.skillsDirectoryURL
        self.service = service
        setupWatcher()
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

    var selectedItemReadOnlyReason: String? {
        guard let selectedItem else { return nil }
        return service.readOnlyReason(for: selectedItem.url, protectedURL: protectedURL)
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
        return selectedItem.isTextFile && !selectedItem.isProtected
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

        if selectedItem.isDirectory && !selectedItem.isSymbolicLink {
            return selectedItem.url
        }

        return selectedItem.url.deletingLastPathComponent()
    }

    func reloadIfNeeded() {
        guard !hasLoadedOnce else { return }
        reload()
    }

    func reload() {
        isLoading = true
        errorMessage = nil

        do {
            let snapshot = try service.loadTree(for: agentType)
            entries = snapshot.entries
            rootExists = snapshot.rootExists
            restartWatcher(with: snapshot.watchedDirectories)
            normalizeSelection()
        } catch {
            entries = []
            rootExists = false
            errorMessage = error.localizedDescription
            watcher.stopWatching()
        }

        hasLoadedOnce = true
        isLoading = false
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
        selectedItemID = findItem(withID: newURL.standardizedFileURL.path, in: entries)?.id
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
        selectedItemID = findItem(withID: newURL.standardizedFileURL.path, in: entries)?.id
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

        reload()
        selectedItemID = findItem(withID: newURL.standardizedFileURL.path, in: entries)?.id
    }

    func deleteSelectedItem() throws {
        guard let selectedItem else { return }
        let parentID = selectedItem.url.deletingLastPathComponent().standardizedFileURL.path

        try service.deleteItem(at: selectedItem.url, rootURL: rootURL, protectedURL: protectedURL)

        reload()
        selectedItemID = findItem(withID: parentID, in: entries)?.id
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

    private func setupWatcher() {
        watcher.onChange
            .sink { [weak self] in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    private func restartWatcher(with paths: [URL]) {
        let uniquePaths = Array(Set(paths.map { $0.standardizedFileURL }))
            .sorted { $0.path < $1.path }
        watcher.startWatching(paths: uniquePaths)
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
            if let children = item.children, let found = findItem(withID: id, in: children) {
                return found
            }
        }
        return nil
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
}
