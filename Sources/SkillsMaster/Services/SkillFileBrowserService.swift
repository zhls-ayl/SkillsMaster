import Foundation

struct SkillFileBrowserService: Sendable {

    private let detailService = AgentFileBrowserService()

    func loadSnapshot(rootURL: URL) throws -> SkillRelatedFilesSnapshot {
        let standardizedRoot = rootURL.standardizedFileURL
        let rootSkillMDURL = standardizedRoot.appendingPathComponent("SKILL.md").standardizedFileURL

        var watchPaths = Set<URL>([standardizedRoot])
        var extraItemCount = 0
        var hasNestedDirectories = false

        let nodes = try loadNodes(
            at: standardizedRoot,
            rootURL: standardizedRoot,
            rootSkillMDURL: rootSkillMDURL,
            depth: 0,
            watchPaths: &watchPaths,
            extraItemCount: &extraItemCount,
            hasNestedDirectories: &hasNestedDirectories
        )

        return SkillRelatedFilesSnapshot(
            nodes: nodes,
            watchPaths: watchPaths.sorted { $0.path < $1.path },
            extraItemCount: extraItemCount,
            hasNestedDirectories: hasNestedDirectories
        )
    }

    func loadItemDetails(at itemURL: URL) throws -> AgentFileDetails {
        try detailService.loadItemDetails(at: itemURL)
    }

    private func loadNodes(
        at directoryURL: URL,
        rootURL: URL,
        rootSkillMDURL: URL,
        depth: Int,
        watchPaths: inout Set<URL>,
        extraItemCount: inout Int,
        hasNestedDirectories: inout Bool
    ) throws -> [SkillRelatedFileNode] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]

        let contents = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        var nodes: [SkillRelatedFileNode] = []

        for url in contents {
            let standardizedURL = url.standardizedFileURL

            if shouldSkip(standardizedURL, rootSkillMDURL: rootSkillMDURL) {
                continue
            }

            let values = try? standardizedURL.resourceValues(forKeys: keys)
            let isSymbolicLink = values?.isSymbolicLink == true || SymlinkManager.isSymlink(at: standardizedURL)
            let isDirectory = isDirectoryLike(standardizedURL, values: values)
            let isHidden = values?.isHidden == true || standardizedURL.lastPathComponent.hasPrefix(".")

            if isDirectory && !isSymbolicLink {
                watchPaths.insert(standardizedURL)
                if depth >= 0 {
                    hasNestedDirectories = true
                }
            }

            extraItemCount += 1

            let item = AgentFileItem(
                url: standardizedURL,
                relativePath: relativePath(for: standardizedURL, rootURL: rootURL),
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink,
                isHidden: isHidden,
                isProtected: false,
                protectionReason: nil,
                loadedChildCount: nil
            )

            let children: [SkillRelatedFileNode]
            if isDirectory && !isSymbolicLink {
                children = try loadNodes(
                    at: standardizedURL,
                    rootURL: rootURL,
                    rootSkillMDURL: rootSkillMDURL,
                    depth: depth + 1,
                    watchPaths: &watchPaths,
                    extraItemCount: &extraItemCount,
                    hasNestedDirectories: &hasNestedDirectories
                )
            } else {
                children = []
            }

            nodes.append(SkillRelatedFileNode(item: item, children: children))
        }

        return nodes.sorted(by: compareNodes)
    }

    private func shouldSkip(_ url: URL, rootSkillMDURL: URL) -> Bool {
        if url.standardizedFileURL == rootSkillMDURL {
            return true
        }
        return url.lastPathComponent == ".DS_Store"
    }

    private func compareNodes(lhs: SkillRelatedFileNode, rhs: SkillRelatedFileNode) -> Bool {
        if lhs.item.isDirectory != rhs.item.isDirectory {
            return lhs.item.isDirectory && !rhs.item.isDirectory
        }
        return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
    }

    private func isDirectoryLike(_ url: URL, values: URLResourceValues?) -> Bool {
        if values?.isDirectory == true {
            return true
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.path
        let itemPath = url.path
        guard itemPath.hasPrefix(rootPath) else { return url.lastPathComponent }

        let relative = String(itemPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? "." : relative
    }
}
