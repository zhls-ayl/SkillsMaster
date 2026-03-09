import Foundation

/// `GitService` 封装了仓库内所有 git CLI 操作，是 F10（One-Click Install）和 F12（Update Check）的基础设施。
///
/// 由于 git 操作会涉及临时目录、filesystem read/write 和外部进程调用，
/// 这里使用 `actor` 保证 thread safety，避免多个任务同时执行 git 命令导致 data race。
///
/// 实现上复用了 `AgentDetector` 已验证过的 `Process` 调用模式，用统一方式执行外部命令。
actor GitService {

    // MARK: - Error Types

    /// 与 git 操作相关的错误类型。
    /// 通过 `LocalizedError` 提供适合展示给用户的错误描述。
    enum GitError: Error, LocalizedError {
        /// 系统中未安装 Git。
        case gitNotInstalled
        /// Git clone 失败，并附带错误信息。
        case cloneFailed(String)
        /// repository URL 格式不合法。
        case invalidRepoURL(String)
        /// 无法获取 tree hash（`git rev-parse` 失败）。
        case hashResolutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .gitNotInstalled:
                "Git is not installed. Please install git to use this feature."
            case .cloneFailed(let message):
                "Failed to clone repository: \(message)"
            case .invalidRepoURL(let url):
                "Invalid repository URL: \(url)"
            case .hashResolutionFailed(let message):
                "Failed to resolve tree hash: \(message)"
            }
        }
    }

    // MARK: - Data Types

    /// 从远端 repository 中扫描得到的 skill 信息。
    /// 这里实现 `Identifiable`，方便 SwiftUI 的 `ForEach` 直接使用。
    struct DiscoveredSkill: Identifiable {
        /// 唯一标识：skill 目录名，例如 `find-skills`。
        let id: String
        /// skill 在 repository 内的相对目录，例如 `skills/find-skills`。
        let folderPath: String
        /// `SKILL.md` 在 repository 内的相对路径，例如 `skills/find-skills/SKILL.md`。
        let skillMDPath: String
        /// 已解析出的 `SKILL.md` metadata。
        let metadata: SkillMetadata
        /// `SKILL.md` 的 Markdown 正文。
        let markdownBody: String
    }

    // MARK: - Public Methods

    /// 检查系统中是否可用 Git。
    /// 这里通过 `which git` 判断，退出码为 `0` 表示已安装。
    func checkGitAvailable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 把 repository clone 到临时目录，支持 shallow clone 与 full clone。
    ///
    /// - Parameters:
    ///   - repoURL: 完整 repository URL，例如 `https://github.com/vercel-labs/skills.git`
    ///   - shallow: 为 `true` 时使用 `--depth 1`，只拉最新提交；为 `false` 时执行完整 clone
    /// - Returns: clone 后的本地临时目录 URL
    /// - Throws: `GitError.gitNotInstalled` 或 `GitError.cloneFailed`
    ///
    /// shallow clone 更快、更省空间；full clone 则允许后续访问完整 git history。
    func cloneRepo(repoURL: String, shallow: Bool, httpAuthorization: String? = nil) async throws -> URL {
        // 创建临时目录，例如 `/tmp/SkillsMaster-<UUID>/`。
        // 使用 `UUID` 可以确保每次 clone 的目标目录都不同，避免冲突。
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-\(UUID().uuidString)")

        // 根据 `shallow` 参数决定 clone 深度。
        var arguments: [String] = []
        if let httpAuthorization {
            arguments += ["-c", "http.extraHeader=\(httpAuthorization)"]
        }
        arguments += ["clone", "--quiet"]
        if shallow {
            arguments += ["--depth", "1"]
        }
        arguments += [repoURL, tempDir.path]

        let output = try await runGitCommand(
            arguments: arguments,
            workingDirectory: nil
        )

        // 通过检查目录是否存在来确认 clone 是否成功。
        guard FileManager.default.fileExists(atPath: tempDir.path) else {
            throw GitError.cloneFailed(output)
        }

        return tempDir
    }

    /// shallow clone 的便捷方法，用于保持 API 兼容性。
    ///
    /// 内部直接调用 `cloneRepo(shallow: true)`，等价于 `git clone --depth 1`。
    func shallowClone(repoURL: String, httpAuthorization: String? = nil) async throws -> URL {
        try await cloneRepo(repoURL: repoURL, shallow: true, httpAuthorization: httpAuthorization)
    }

    /// 获取 repository `HEAD` 对应的 commit hash（完整 40 位 SHA-1）。
    ///
    /// - Parameter repoDir: repository 本地目录
    /// - Returns: 完整 commit hash 字符串
    /// - Throws: `GitError.hashResolutionFailed`
    ///
    /// 注意这里拿到的是 **commit hash**，不是 tree hash。
    /// GitHub compare URL 需要依赖 commit hash 才能正确跳转。
    func getCommitHash(in repoDir: URL) async throws -> String {
        let output = try await runGitCommand(
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: repoDir
        )
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw GitError.hashResolutionFailed("Empty commit hash")
        }
        return hash
    }

    /// 检查 repository working tree 是否存在未提交改动。
    ///
    /// 这里把 tracked / untracked 文件都视为 dirty，避免将 custom repository 的本地 clone
    /// 误当成可安全复用缓存的只读镜像。
    func isWorkingTreeDirty(in repoDir: URL) async throws -> Bool {
        let output = try await runGitCommand(
            arguments: ["status", "--porcelain", "--untracked-files=all"],
            workingDirectory: repoDir
        )
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 在 git history 中查找“产生指定 tree hash 的 commit”，用于给旧 skill 回填 commit hash。
    ///
    /// - Parameters:
    ///   - treeHash: 目标 tree hash，来自 `lockEntry.skillFolderHash`
    ///   - folderPath: skill 在 repository 中的相对路径，例如 `skills/find-skills`
    ///   - repoDir: 完整 clone 的 repository 目录；这里不能是 shallow clone
    /// - Returns: 匹配到的 commit hash；如果找不到则返回 `nil`
    ///
    /// 实现思路：
    /// 1. 先通过 `git log --format=%H -- <folderPath>` 找到所有修改过该路径的 commit
    /// 2. 再对每个 commit 执行 `git rev-parse <commit>:<folderPath>`，取出当时的 tree hash
    /// 3. 与目标 `treeHash` 对比，命中后返回对应的 commit hash
    ///
    /// 这个方法相对较慢，因此只会在 `CommitHashCache` 没有缓存时触发；一旦命中结果，就会写入 cache。
    func findCommitForTreeHash(
        treeHash: String, folderPath: String, in repoDir: URL
    ) async throws -> String? {
        // 1. 先找出所有修改过该路径的 commit。
        // `--format=%H` 只输出 commit hash，每行一个。
        let logOutput = try await runGitCommand(
            arguments: ["log", "--format=%H", "--", folderPath],
            workingDirectory: repoDir
        )

        // 按行拆分，得到 commit hash 列表。
        let commits = logOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map(String.init)

        // 2. 逐个 commit 检查该路径下的 tree hash。
        for commit in commits {
            do {
                let output = try await runGitCommand(
                    arguments: ["rev-parse", "\(commit):\(folderPath)"],
                    workingDirectory: repoDir
                )
                let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
                // 3. 一旦找到匹配的 tree hash，就返回对应的 commit hash。
                if hash == treeHash {
                    return commit
                }
            } catch {
                // 有些历史 commit 可能还没有这个路径（例如重命名前），这种情况直接跳过。
                continue
            }
        }

        // 遍历完所有 commit 仍未命中。
        return nil
    }

    /// 获取指定路径对应的 git tree hash。
    ///
    /// - Parameters:
    ///   - path: repository 内的相对路径，例如 `skills/find-skills`
    ///   - repoDir: repository 本地目录
    /// - Returns: tree hash 字符串
    /// - Throws: `GitError.hashResolutionFailed`
    ///
    /// `git rev-parse HEAD:<path>` 会返回 `HEAD` 提交下该路径的 tree hash。
    /// 只要路径下任意文件变化，这个 hash 就会跟着变化，因此可用于更新检测。
    func getTreeHash(for path: String, in repoDir: URL) async throws -> String {
        let output = try await runGitCommand(
            arguments: ["rev-parse", "HEAD:\(path)"],
            workingDirectory: repoDir
        )
        let hash = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw GitError.hashResolutionFailed("Empty hash for path: \(path)")
        }
        return hash
    }

    /// 扫描已 clone 的 repository 目录，发现其中所有包含 `SKILL.md` 的 skill。
    ///
    /// - Parameters:
    ///   - repoDir: 已 clone repository 的本地目录
    ///   - includeHiddenPaths: 是否扫描隐藏路径（例如 `.claude/`）；默认开启
    /// - Returns: 扫描到的全部 skills
    ///
    /// 实现上会递归遍历 repository 目录树，查找 `SKILL.md`，并通过 `SkillMDParser` 解析 metadata。
    ///
    /// 默认只构建轻量索引，不在扫描阶段保留全部 Markdown 正文，避免大仓库浏览时占用过多时间和内存。
    func scanSkillsInRepo(repoDir: URL, includeHiddenPaths: Bool = true) -> [DiscoveredSkill] {
        let fm = FileManager.default
        var discovered: [DiscoveredSkill] = []
        let repoDirPath = repoDir.standardizedFileURL.path

        // `enumerator` 会递归遍历整个目录树。
        // `includingPropertiesForKeys` 可以预取文件属性，减少后续查询开销。
        // 这里不能使用 `.skipsHiddenFiles`，因为有些 repo 会把 skill 放在 `.claude/skills/` 这类隐藏目录下。
        // 因此当前策略是：保留隐藏目录扫描，但手动跳过 `.git`。
        guard let enumerator = fm.enumerator(
            at: repoDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []  // Don't skip hidden files — .claude/skills/ is hidden but valid
        ) else {
            return []
        }

        // 收集所有 `SKILL.md` 路径，并跳过 `.git` 目录。
        var skillMDURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            // 跳过 `.git` 目录：它体积大，而且不会包含真正的 skill。
            // 这里使用 `lastPathComponent`，确保任意层级下的 `.git` 都能被识别。
            if fileURL.lastPathComponent == ".git" {
                // `skipDescendants()` 会告诉 `enumerator` 不再继续深入这个目录。
                enumerator.skipDescendants()
                continue
            }
            if fileURL.lastPathComponent == "SKILL.md" {
                let fullPath = fileURL.standardizedFileURL.path
                if fullPath.hasPrefix(repoDirPath) {
                    var relative = String(fullPath.dropFirst(repoDirPath.count))
                    if relative.hasPrefix("/") {
                        relative = String(relative.dropFirst())
                    }
                    // custom repo 可以关闭 hidden-path 扫描，避免隐藏目录中的镜像副本带来歧义。
                    if !includeHiddenPaths && containsHiddenPathSegment(relative) {
                        continue
                    }
                }
                skillMDURLs.append(fileURL)
            }
        }

        // Parse each SKILL.md
        for skillMDURL in skillMDURLs {
            let skillDir = skillMDURL.deletingLastPathComponent()
            let skillName = skillDir.lastPathComponent

            // 计算相对于 repository 根目录的路径。
            // 例如：`repoDir = /tmp/xxx/`，`skillDir = /tmp/xxx/skills/find-skills/`，
            // 则 `folderPath = "skills/find-skills"`。
            let repoDirPath = repoDir.standardizedFileURL.path
            let skillDirPath = skillDir.standardizedFileURL.path
            let folderPath: String
            if skillDirPath.hasPrefix(repoDirPath) {
                // `dropFirst` 会去掉前缀路径。
                var relative = String(skillDirPath.dropFirst(repoDirPath.count))
                // 如果存在前导 `/`，就去掉。
                if relative.hasPrefix("/") {
                    relative = String(relative.dropFirst())
                }
                // 如果存在结尾 `/`，就去掉。
                if relative.hasSuffix("/") {
                    relative = String(relative.dropLast())
                }
                folderPath = relative
            } else {
                folderPath = skillName
            }

            let skillMDPath = folderPath.isEmpty
                ? "SKILL.md"
                : "\(folderPath)/SKILL.md"

            // 列表索引阶段只解析 metadata，正文在详情页按需加载。
            do {
                let metadata = try SkillMDParser.parseMetadata(fileURL: skillMDURL)
                discovered.append(DiscoveredSkill(
                    id: skillName,
                    folderPath: folderPath,
                    skillMDPath: skillMDPath,
                    metadata: metadata,
                    markdownBody: ""
                ))
            } catch {
                // 如果解析失败，就回退到目录名作为最小信息，不阻断整次扫描。
                discovered.append(DiscoveredSkill(
                    id: skillName,
                    folderPath: folderPath,
                    skillMDPath: skillMDPath,
                    metadata: SkillMetadata(name: skillName, description: ""),
                    markdownBody: ""
                ))
            }
        }

        // 按 `skill id` 去重。
        // 如果出现重复项（例如隐藏目录镜像 + 正常路径），优先保留非隐藏且层级更浅的路径。
        var uniqueByID: [String: DiscoveredSkill] = [:]
        for skill in discovered {
            if let existing = uniqueByID[skill.id] {
                if shouldPrefer(skill, over: existing) {
                    uniqueByID[skill.id] = skill
                }
            } else {
                uniqueByID[skill.id] = skill
            }
        }

        // 最后按 `id` 排序；若 `id` 相同，则再用 `folderPath` 作为稳定的 tie-breaker。
        return uniqueByID.values.sorted {
            let lhsID = $0.id.lowercased()
            let rhsID = $1.id.lowercased()
            if lhsID == rhsID {
                return $0.folderPath.lowercased() < $1.folderPath.lowercased()
            }
            return lhsID < rhsID
        }
    }

    private func containsHiddenPathSegment(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// 当多个扫描结果共享相同 `skill id` 时，选择更优的候选项。
    private func shouldPrefer(_ lhs: DiscoveredSkill, over rhs: DiscoveredSkill) -> Bool {
        let lhsHidden = containsHiddenPathComponent(lhs.folderPath)
        let rhsHidden = containsHiddenPathComponent(rhs.folderPath)
        if lhsHidden != rhsHidden {
            return !lhsHidden
        }

        let lhsDepth = lhs.folderPath.split(separator: "/").count
        let rhsDepth = rhs.folderPath.split(separator: "/").count
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }

        return lhs.folderPath.lowercased() < rhs.folderPath.lowercased()
    }

    private func containsHiddenPathComponent(_ folderPath: String) -> Bool {
        folderPath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// 读取 repository 内单个 skill 的完整 `SKILL.md` 内容。
    func loadSkillContent(skillMDPath: String, in repoDir: URL) throws -> SkillMDParser.ParseResult {
        let fileURL = repoDir.appendingPathComponent(skillMDPath)
        return try SkillMDParser.parse(fileURL: fileURL)
    }

    /// 清理临时目录。
    /// 在安装完成或取消后调用，用于释放磁盘空间。
    func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 对已 clone 的 repository 执行 `pull`，获取最新变更。
    ///
    /// - Parameter repoDir: 已 clone repository 的本地目录（必须包含 `.git` 子目录）
    /// - Throws: 当 `git pull` 以非零状态退出时抛出 `GitError.cloneFailed`
    ///
    /// 效果上等价于在该目录下执行 `git pull`。
    func pull(repoDir: URL, httpAuthorization: String? = nil) async throws {
        var arguments: [String] = []
        if let httpAuthorization {
            arguments += ["-c", "http.extraHeader=\(httpAuthorization)"]
        }
        arguments += ["pull", "--quiet"]
        _ = try await runGitCommand(
            arguments: arguments,
            workingDirectory: repoDir
        )
    }

    // MARK: - URL Normalization（纯函数，不需要 actor isolation）

    /// 根据 git repository URL 生成 GitHub web URL。
    ///
    /// - Parameter sourceUrl: git repository URL，例如 `https://github.com/owner/repo.git`
    /// - Returns: GitHub web URL；如果不是 GitHub URL，则返回 `nil`
    ///
    /// 这里使用 `nonisolated`，因为它是纯函数，不依赖 actor 的可变状态。
    nonisolated static func githubWebURL(from sourceUrl: String) -> String? {
        // 这里只处理 GitHub URL。
        guard sourceUrl.lowercased().contains("github.com") else { return nil }

        var url = sourceUrl
        // 去掉 `.git` 后缀。
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }
        // 去掉结尾的 `/`。
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        return url
    }

    /// 规范化用户输入的 repository URL，兼容多种输入格式。
    ///
    /// 当前支持：
    /// - `owner/repo`，自动补全为 GitHub HTTPS URL
    /// - `https://github.com/owner/repo`
    /// - `https://github.com/owner/repo.git`
    /// - `git@github.com:owner/repo.git`
    /// - `git@gitlab.com:owner/repo.git`
    ///
    /// - Parameter input: 用户输入的 repository 地址
    /// - Returns: `(full repoURL, source)`
    /// - Throws: `GitError.invalidRepoURL`
    ///
    /// 这里同样使用 `nonisolated`，因为它是纯函数，不依赖 actor 可变状态。
    nonisolated static func normalizeRepoURL(_ input: String) throws -> (repoURL: String, source: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw GitError.invalidRepoURL(input)
        }

        // Case 0：SSH URL，例如 `git@hostname:org/repo.git`。
        // 这种格式会原样透传，SSH 认证由系统环境负责。
        if trimmed.lowercased().hasPrefix("git@") {
            // 从 `:` 后面的路径里提取 `org/repo`。
            var source = trimmed
            if let colonIdx = source.firstIndex(of: ":") {
                source = String(source[source.index(after: colonIdx)...])
            }
            // 为展示用的 `source` 去掉 `.git` 后缀。
            if source.hasSuffix(".git") {
                source = String(source.dropLast(4))
            }
            // 确保 clone URL 以 `.git` 结尾。
            var repoURL = trimmed
            if !repoURL.hasSuffix(".git") {
                repoURL += ".git"
            }
            return (repoURL: repoURL, source: source)
        }

        // Case 1：完整 HTTPS URL。
        if trimmed.lowercased().hasPrefix("https://") {
            // 从 URL 中提取 `owner/repo` 作为展示用 `source`。
            var source = trimmed
            // 去掉 `https://github.com/` 前缀。
            if let range = source.range(of: "https://github.com/", options: .caseInsensitive) {
                source = String(source[range.upperBound...])
            }
            // 去掉 `.git` 后缀。
            if source.hasSuffix(".git") {
                source = String(source.dropLast(4))
            }
            // 去掉结尾的 `/`。
            if source.hasSuffix("/") {
                source = String(source.dropLast())
            }

            // 确保 `repoURL` 最终以 `.git` 结尾。
            var repoURL = trimmed
            if !repoURL.hasSuffix(".git") {
                // 去掉结尾的 `/`。
                if repoURL.hasSuffix("/") {
                    repoURL = String(repoURL.dropLast())
                }
                repoURL += ".git"
            }

            return (repoURL: repoURL, source: source)
        }

        // Case 2：`owner/repo` 格式。
        // 这里要求输入里必须且只能包含一个 `/`。
        let components = trimmed.split(separator: "/")
        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            throw GitError.invalidRepoURL(input)
        }

        // 去掉 repo 名里可能存在的 `.git` 后缀。
        var repoName = String(components[1])
        if repoName.hasSuffix(".git") {
            repoName = String(repoName.dropLast(4))
        }

        let source = "\(components[0])/\(repoName)"
        let repoURL = "https://github.com/\(source).git"
        return (repoURL: repoURL, source: source)
    }

    // MARK: - Private Methods

    /// 执行 git 命令，并返回 `stdout` 输出。
    ///
    /// - Parameters:
    ///   - arguments: git 参数列表（不包含 `git` 本身）
    ///   - workingDirectory: 工作目录；为 `nil` 时使用默认目录
    /// - Returns: 命令的 `stdout` 内容
    /// - Throws: `GitError`
    ///
    /// 实现上使用 `Process API`，并复用了 `AgentDetector` 已验证过的执行模式。
    private func runGitCommand(arguments: [String], workingDirectory: URL?) async throws -> String {
        // First find git's full path (via which git)
        let gitPath = try await findGitPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments

        // 如果传入了工作目录，就在这里设置。
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitError.cloneFailed(error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // 非零退出码表示命令执行失败。
        guard process.terminationStatus == 0 else {
            let errorMessage = stderr.isEmpty ? stdout : stderr
            let trimmed = errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.localizedCaseInsensitiveContains("Host key verification failed") {
                throw GitError.cloneFailed(
                    "\(trimmed)\n\nSSH host key verification failed. Run `ssh -T git@<your-host>` once in Terminal and trust the host key, then retry Sync."
                )
            }
            throw GitError.cloneFailed(trimmed)
        }

        return stdout
    }

    /// 查找 git 可执行文件的完整路径。
    /// 会先检查常见安装路径，避免每次都额外执行 `which`。
    private func findGitPath() async throws -> String {
        let commonPaths = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw GitError.gitNotInstalled
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else {
                throw GitError.gitNotInstalled
            }
            return path
        } catch is GitError {
            throw GitError.gitNotInstalled
        } catch {
            throw GitError.gitNotInstalled
        }
    }
}
