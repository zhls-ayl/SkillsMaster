import Foundation
import UniformTypeIdentifiers

struct AgentFileBrowserService: Sendable {

    enum CreateKind {
        case file
        case folder
    }

    enum BrowserError: Error, LocalizedError {
        case configDirectoryUnavailable(AgentType)
        case invalidName
        case itemAlreadyExists(URL)
        case itemNotFound(URL)
        case notDirectory(URL)
        case protectedPath(String)

        var errorDescription: String? {
            switch self {
            case .configDirectoryUnavailable(let agentType):
                return AppLocalization.format("%@ has no available configuration root directory.", agentType.displayName)
            case .invalidName:
                return AppLocalization.string("The name cannot be empty and cannot contain /, . or ..")
            case .itemAlreadyExists(let url):
                return AppLocalization.format("Target already exists: %@", url.lastPathComponent)
            case .itemNotFound(let url):
                return AppLocalization.format("Target does not exist: %@", url.path)
            case .notDirectory(let url):
                return AppLocalization.format("Target is not a directory: %@", url.path)
            case .protectedPath(let reason):
                return reason
            }
        }
    }

    func loadRootSnapshot(for agentType: AgentType) throws -> AgentFileRootSnapshot {
        guard let rootURL = agentType.configDirectoryURL else {
            throw BrowserError.configDirectoryUnavailable(agentType)
        }

        return loadRootSnapshot(rootURL: rootURL, protectedURL: agentType.skillsDirectoryURL)
    }

    func loadRootSnapshot(rootURL: URL, protectedURL: URL) -> AgentFileRootSnapshot {
        let fm = FileManager.default
        let standardizedRoot = rootURL.standardizedFileURL

        guard fm.fileExists(atPath: standardizedRoot.path) else {
            return AgentFileRootSnapshot(
                entries: [],
                rootExists: false,
                watchBaseURL: nearestExistingAncestor(for: standardizedRoot)
            )
        }

        let entries = (try? loadDirectoryContents(
            at: standardizedRoot,
            rootURL: standardizedRoot,
            protectedURL: protectedURL.standardizedFileURL
        )) ?? []

        return AgentFileRootSnapshot(
            entries: entries,
            rootExists: true,
            watchBaseURL: standardizedRoot
        )
    }

    func loadDirectoryContents(
        at directoryURL: URL,
        rootURL: URL,
        protectedURL: URL
    ) throws -> [AgentFileItem] {
        let directoryURL = directoryURL.standardizedFileURL
        let rootURL = rootURL.standardizedFileURL
        let protectedURL = protectedURL.standardizedFileURL
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) else {
            throw BrowserError.itemNotFound(directoryURL)
        }
        guard isDirectory.boolValue else {
            throw BrowserError.notDirectory(directoryURL)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey
        ]

        let contents = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        let entries = contents.map {
            buildEntry(at: $0, rootURL: rootURL, protectedURL: protectedURL)
        }

        return entries.sorted(by: compareEntries)
    }

    func loadItemDetails(at itemURL: URL) throws -> AgentFileDetails {
        let itemURL = itemURL.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        let values = try itemURL.resourceValues(forKeys: keys)
        let isDirectory = isDirectoryLike(itemURL, values: values)
        let isSymbolicLink = values.isSymbolicLink == true || SymlinkManager.isSymlink(at: itemURL)

        return AgentFileDetails(
            fileSize: isDirectory ? nil : values.fileSize,
            modifiedDate: values.contentModificationDate,
            isTextFile: !isDirectory && !isSymbolicLink && isProbablyTextFile(at: itemURL)
        )
    }

    func readOnlyReason(for itemURL: URL, protectedURL: URL) -> String? {
        skillsProtectionReason(for: itemURL.standardizedFileURL, protectedURL: protectedURL.standardizedFileURL)
    }

    func canCreateChild(in directoryURL: URL, protectedURL: URL) -> Bool {
        creationDeniedReason(
            in: directoryURL.standardizedFileURL,
            protectedURL: protectedURL.standardizedFileURL
        ) == nil
    }

    func canMutateItem(at itemURL: URL, rootURL: URL, protectedURL: URL) -> Bool {
        mutationDeniedReason(
            for: itemURL.standardizedFileURL,
            rootURL: rootURL.standardizedFileURL,
            protectedURL: protectedURL.standardizedFileURL
        ) == nil
    }

    func createItem(
        named rawName: String,
        kind: CreateKind,
        in directoryURL: URL,
        rootURL: URL,
        protectedURL: URL,
        replaceExisting: Bool = false
    ) throws -> URL {
        let rootURL = rootURL.standardizedFileURL
        let protectedURL = protectedURL.standardizedFileURL
        let directoryURL = directoryURL.standardizedFileURL
        let name = try validatedName(rawName)

        if let reason = creationDeniedReason(in: directoryURL, protectedURL: protectedURL) {
            throw BrowserError.protectedPath(reason)
        }

        let targetURL = directoryURL.appendingPathComponent(name)
        if let reason = targetPathDeniedReason(for: targetURL, protectedURL: protectedURL) {
            throw BrowserError.protectedPath(reason)
        }

        try ensureDirectoryExists(at: rootURL)
        try ensureDirectoryExists(at: directoryURL)

        if pathExists(targetURL) {
            guard replaceExisting else {
                throw BrowserError.itemAlreadyExists(targetURL)
            }
            if let reason = mutationDeniedReason(for: targetURL, rootURL: rootURL, protectedURL: protectedURL) {
                throw BrowserError.protectedPath(reason)
            }
            try FileManager.default.removeItem(at: targetURL)
        }

        switch kind {
        case .file:
            FileManager.default.createFile(atPath: targetURL.path, contents: Data())
        case .folder:
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        }

        return targetURL
    }

    func renameItem(
        at itemURL: URL,
        to rawName: String,
        rootURL: URL,
        protectedURL: URL,
        replaceExisting: Bool = false
    ) throws -> URL {
        let rootURL = rootURL.standardizedFileURL
        let protectedURL = protectedURL.standardizedFileURL
        let itemURL = itemURL.standardizedFileURL
        let name = try validatedName(rawName)

        guard pathExists(itemURL) else {
            throw BrowserError.itemNotFound(itemURL)
        }

        if let reason = mutationDeniedReason(for: itemURL, rootURL: rootURL, protectedURL: protectedURL) {
            throw BrowserError.protectedPath(reason)
        }

        let targetURL = itemURL.deletingLastPathComponent().appendingPathComponent(name)
        if targetURL.path == itemURL.path {
            return itemURL
        }

        if let reason = targetPathDeniedReason(for: targetURL, protectedURL: protectedURL) {
            throw BrowserError.protectedPath(reason)
        }

        if pathExists(targetURL) {
            guard replaceExisting else {
                throw BrowserError.itemAlreadyExists(targetURL)
            }
            if let reason = mutationDeniedReason(for: targetURL, rootURL: rootURL, protectedURL: protectedURL) {
                throw BrowserError.protectedPath(reason)
            }
            try FileManager.default.removeItem(at: targetURL)
        }

        try FileManager.default.moveItem(at: itemURL, to: targetURL)
        return targetURL
    }

    func deleteItem(at itemURL: URL, rootURL: URL, protectedURL: URL) throws {
        let rootURL = rootURL.standardizedFileURL
        let protectedURL = protectedURL.standardizedFileURL
        let itemURL = itemURL.standardizedFileURL

        guard pathExists(itemURL) else {
            throw BrowserError.itemNotFound(itemURL)
        }

        if let reason = mutationDeniedReason(for: itemURL, rootURL: rootURL, protectedURL: protectedURL) {
            throw BrowserError.protectedPath(reason)
        }

        try FileManager.default.removeItem(at: itemURL)
    }

    private func buildEntry(at url: URL, rootURL: URL, protectedURL: URL) -> AgentFileItem {
        let standardizedURL = url.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey
        ]
        let values = try? standardizedURL.resourceValues(forKeys: keys)

        let isSymbolicLink = values?.isSymbolicLink == true || SymlinkManager.isSymlink(at: standardizedURL)
        let isDirectory = isDirectoryLike(standardizedURL, values: values)
        let isHidden = values?.isHidden == true || standardizedURL.lastPathComponent.hasPrefix(".")
        let protectionReason = skillsProtectionReason(for: standardizedURL, protectedURL: protectedURL)

        return AgentFileItem(
            url: standardizedURL,
            relativePath: relativePath(for: standardizedURL, rootURL: rootURL),
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            isHidden: isHidden,
            isProtected: protectionReason != nil,
            protectionReason: protectionReason,
            loadedChildCount: nil
        )
    }

    private func compareEntries(lhs: AgentFileItem, rhs: AgentFileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func isDirectoryLike(_ url: URL, values: URLResourceValues?) -> Bool {
        if values?.isDirectory == true {
            return true
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw BrowserError.invalidName
        }
        return name
    }

    private func ensureDirectoryExists(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func mutationDeniedReason(for itemURL: URL, rootURL: URL, protectedURL: URL) -> String? {
        if itemURL.path == rootURL.path {
            return AppLocalization.string("The Agent root directory itself cannot be renamed or deleted here.")
        }
        return skillsProtectionReason(for: itemURL, protectedURL: protectedURL)
    }

    private func creationDeniedReason(in directoryURL: URL, protectedURL: URL) -> String? {
        skillsProtectionReason(for: directoryURL, protectedURL: protectedURL)
    }

    private func targetPathDeniedReason(for targetURL: URL, protectedURL: URL) -> String? {
        skillsProtectionReason(for: targetURL, protectedURL: protectedURL)
    }

    private func skillsProtectionReason(for url: URL, protectedURL: URL) -> String? {
        let itemPath = url.standardizedFileURL.path
        let protectedPath = protectedURL.standardizedFileURL.path

        guard itemPath == protectedPath || itemPath.hasPrefix(protectedPath + "/") else {
            return nil
        }

        return AppLocalization.string("The `skills/` directory and its contents are managed by SkillsMaster and are read-only in Agent Files.")
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.path
        let itemPath = url.path
        guard itemPath.hasPrefix(rootPath) else { return url.lastPathComponent }

        let relative = String(itemPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }

    private func pathExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || SymlinkManager.isSymlink(at: url)
    }

    private func nearestExistingAncestor(for url: URL) -> URL {
        let fm = FileManager.default
        var candidate = url

        while !fm.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }

        return candidate
    }

    private func isProbablyTextFile(at url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .text) {
            return true
        }

        let lowercaseName = url.lastPathComponent.lowercased()
        let knownPlainTextNames: Set<String> = [
            ".env",
            ".gitignore",
            ".gitconfig",
            ".editorconfig",
            ".npmrc",
            ".yarnrc",
            ".zshrc",
            ".bashrc",
            ".bash_profile",
            "readme",
            "license"
        ]
        if url.pathExtension.isEmpty && knownPlainTextNames.contains(lowercaseName) {
            return true
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 4096) else {
            return false
        }

        if data.contains(0) {
            return false
        }

        return String(data: data, encoding: .utf8) != nil
            || String(data: data, encoding: .ascii) != nil
    }
}
