import Foundation
import UniformTypeIdentifiers

final class AgentFileBrowserService {

    enum CreateKind {
        case file
        case folder
    }

    enum BrowserError: Error, LocalizedError {
        case configDirectoryUnavailable(AgentType)
        case invalidName
        case itemAlreadyExists(URL)
        case itemNotFound(URL)
        case protectedPath(String)

        var errorDescription: String? {
            switch self {
            case .configDirectoryUnavailable(let agentType):
                return "\(agentType.displayName) 没有可用的配置根目录。"
            case .invalidName:
                return "名称不能为空，且不能包含 /、. 或 ..。"
            case .itemAlreadyExists(let url):
                return "目标已存在：\(url.lastPathComponent)"
            case .itemNotFound(let url):
                return "目标不存在：\(url.path)"
            case .protectedPath(let reason):
                return reason
            }
        }
    }

    func loadTree(for agentType: AgentType) throws -> AgentFileTreeSnapshot {
        guard let rootURL = agentType.configDirectoryURL else {
            throw BrowserError.configDirectoryUnavailable(agentType)
        }

        return loadTree(rootURL: rootURL, protectedURL: agentType.skillsDirectoryURL)
    }

    func loadTree(rootURL: URL, protectedURL: URL) -> AgentFileTreeSnapshot {
        let fm = FileManager.default
        let standardizedRoot = rootURL.standardizedFileURL
        let standardizedProtected = protectedURL.standardizedFileURL

        guard fm.fileExists(atPath: standardizedRoot.path) else {
            return AgentFileTreeSnapshot(
                entries: [],
                watchedDirectories: [nearestExistingAncestor(for: standardizedRoot)],
                rootExists: false
            )
        }

        var watchedDirectories: [URL] = []
        let entries = loadEntries(
            in: standardizedRoot,
            rootURL: standardizedRoot,
            protectedURL: standardizedProtected,
            watchedDirectories: &watchedDirectories
        )

        return AgentFileTreeSnapshot(
            entries: entries,
            watchedDirectories: watchedDirectories,
            rootExists: true
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

    private func loadEntries(
        in directoryURL: URL,
        rootURL: URL,
        protectedURL: URL,
        watchedDirectories: inout [URL]
    ) -> [AgentFileItem] {
        watchedDirectories.append(directoryURL)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isHiddenKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: []
        ) else {
            return []
        }

        let entries = contents.compactMap { url in
            buildEntry(
                at: url,
                rootURL: rootURL,
                protectedURL: protectedURL,
                watchedDirectories: &watchedDirectories
            )
        }

        return entries.sorted(by: compareEntries)
    }

    private func buildEntry(
        at url: URL,
        rootURL: URL,
        protectedURL: URL,
        watchedDirectories: inout [URL]
    ) -> AgentFileItem? {
        let standardizedURL = url.standardizedFileURL

        let resourceValues = try? standardizedURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])

        let isSymbolicLink = resourceValues?.isSymbolicLink == true || SymlinkManager.isSymlink(at: standardizedURL)
        let isDirectory = resourceValues?.isDirectory == true
        let isHidden = resourceValues?.isHidden == true || standardizedURL.lastPathComponent.hasPrefix(".")
        let fileSize = resourceValues?.fileSize
        let modifiedDate = resourceValues?.contentModificationDate
        let protectionReason = skillsProtectionReason(for: standardizedURL, protectedURL: protectedURL)
        let isProtected = protectionReason != nil
        let canTraverseChildren = isDirectory && !isSymbolicLink

        let children: [AgentFileItem]?
        if canTraverseChildren {
            children = loadEntries(
                in: standardizedURL,
                rootURL: rootURL,
                protectedURL: protectedURL,
                watchedDirectories: &watchedDirectories
            )
        } else {
            children = nil
        }

        return AgentFileItem(
            url: standardizedURL,
            relativePath: relativePath(for: standardizedURL, rootURL: rootURL),
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            isHidden: isHidden,
            isTextFile: !isDirectory && !isSymbolicLink && isProbablyTextFile(at: standardizedURL),
            isProtected: isProtected,
            protectionReason: protectionReason,
            fileSize: isDirectory ? nil : fileSize,
            modifiedDate: modifiedDate,
            children: children
        )
    }

    private func compareEntries(lhs: AgentFileItem, rhs: AgentFileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
            return "Agent 根目录本身不可在这里重命名或删除。"
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

        return "`skills/` 目录及其子内容由 SkillsMaster 管理，在 Agent Files 中只读。"
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
