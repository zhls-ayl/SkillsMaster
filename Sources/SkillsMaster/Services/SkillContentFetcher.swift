import Foundation

/// `SkillContentFetcher` 负责为 registry skill 从 GitHub 拉取原始 `SKILL.md` 内容。
///
/// 由于 `skills.sh` 没有提供单个 skill 内容的 JSON API，这里直接访问 GitHub 获取
/// `SKILL.md`。默认优先走 `raw.githubusercontent.com`，若 raw CDN 在当前网络环境下不可达，
/// 则自动回退到 GitHub Contents API（`api.github.com/repos/.../contents/...`）。
///
/// 当前实现需要兼容多种 repository layout：
/// - **Flat layout**：`{skillId}/SKILL.md` 位于 repo 根目录
/// - **Monorepo layout**：`skills/{skillId}/SKILL.md` 位于 `skills/` 子目录
/// - **Plugin-style layout**：`.claude/skills/{skillId}/SKILL.md`
/// - **Root layout**：`SKILL.md` 直接位于 repo 根目录（single-skill repo）
///
/// 此外，GitHub 上真实目录名不一定等于 registry API 返回的 `skillId`。
/// 如果 direct URL lookup 失败，fetcher 会回退到 Git Tree API，按任意层级搜索真实的 `SKILL.md` 路径。
///
/// 整个流程会先尝试 `main` / `master` 两个 branch 与多种 layout 组合；
/// 如果 direct fetch 全部返回 `404`，再进入 Git Tree API fallback。
///
/// 这里使用 `actor` 维护 cache，保证并发访问时的 thread safety，与项目中的其他 `Service actor` 保持一致。
actor SkillContentFetcher {

    /// GitHub raw CDN 在部分网络环境下可能握手失败或被中间网络层拦截。
    /// 一旦确认 raw CDN 不稳定，本轮 app 生命周期内后续请求直接走 GitHub Contents API，
    /// 避免每次都先经历一次 raw 失败。
    private var shouldBypassRawCDN = false

    // MARK: - Error Types

    /// 拉取 skill 内容时可能出现的错误类型。
    ///
    /// 通过 `LocalizedError` 提供可直接展示的错误描述。
    enum FetchError: Error, LocalizedError {
        /// network request 失败（如 timeout、DNS、连接错误）。
        case networkError(String)
        /// 在预期的 GitHub 路径中未找到 `SKILL.md`。
        case notFound
        /// server 返回了未预期的 HTTP status code。
        case invalidResponse(Int)
        /// response body 不是合法的 UTF-8 文本。
        case invalidEncoding

        /// 面向用户展示的错误描述。
        var errorDescription: String? {
            switch self {
            case .networkError(let message):
                "Network error: \(message)"
            case .notFound:
                "SKILL.md not found in repository"
            case .invalidResponse(let code):
                "Server returned status \(code)"
            case .invalidEncoding:
                "Response is not valid UTF-8 text"
            }
        }
    }

    // MARK: - Cache

    /// 内存中的 cache 项，保存拉取结果及其时间戳。
    private var cache: [String: (content: String, fetchedAt: Date)] = [:]

    /// cache 的 TTL 为 10 分钟。
    /// 因为 skill 内容变化频率较低，所以使用更长的缓存时间来减少重复请求。
    private let cacheTTL: TimeInterval = 10 * 60

    // MARK: - Public API

    /// 从 GitHub 拉取某个 registry skill 对应的原始 `SKILL.md` 内容。
    ///
    /// 当前策略是：先查内存 cache，再依次尝试 direct URL；如果全部 `404`，再回退到 Git Tree API。
    /// - Parameters:
    ///   - source: `owner/repo` 格式的 repository 标识
    ///   - skillId: repository 内部的 skill 标识
    /// - Returns: 原始 `SKILL.md` 文本
    /// - Throws: `FetchError`
    func fetchContent(source: String, skillId: String) async throws -> String {
        let cacheKey = "\(source)/\(skillId)"

        // 1. Check cache — return cached content if still fresh
        // Date() creates the current timestamp; timeIntervalSince calculates difference in seconds
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.content
        }

        // 2. Try direct candidate paths: both branch names × supported directory layouts.
        // This is the fast path — works when skillId matches the directory name exactly.
        for branch in ["main", "master"] {
            for path in candidatePaths(skillId: skillId) {
                if let content = try await fetchContentAtPath(
                    source: source,
                    path: path,
                    branch: branch
                ) {
                    cache[cacheKey] = (content: content, fetchedAt: Date())
                    return content
                }
            }
        }

        // 3. Fallback: use GitHub Git Tree API to discover the actual SKILL.md path.
        // The Tree API returns the entire repo file tree in a single request (recursive=1),
        // so we can find SKILL.md at any depth without multiple API calls.
        // This handles repos where the directory name differs from the skillId,
        // or where SKILL.md is nested in an unexpected location.
        if let content = try await discoverViaTreeAPI(source: source, skillId: skillId) {
            cache[cacheKey] = (content: content, fetchedAt: Date())
            return content
        }

        // 4. All attempts failed — SKILL.md not found
        throw FetchError.notFound
    }

    /// Clear all cached content (for manual refresh scenarios)
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Internal Helpers

    /// Build the raw GitHub content URL for a SKILL.md file
    ///
    /// GitHub serves raw file content at `raw.githubusercontent.com` without HTML wrapping.
    /// URL pattern: `https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}/SKILL.md`
    ///
    /// This is an `internal` (default access) method so tests can verify URL construction
    /// without making actual network requests.
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - path: Relative path to the skill directory (e.g., "my-skill" or "skills/my-skill")
    ///   - branch: Git branch name ("main" or "master")
    /// - Returns: Fully constructed URL for the raw SKILL.md file
    func buildRawURL(source: String, path: String, branch: String) -> URL {
        // Force-unwrap is safe here because the URL components are controlled by us.
        // `raw.githubusercontent.com` is GitHub's CDN for serving raw file content —
        // it returns plain text without any HTML wrapping or GitHub UI.
        //
        // When `path` is empty (root-level SKILL.md), we must avoid producing a double
        // slash like `/{branch}//SKILL.md`. Instead, emit `/{branch}/SKILL.md`.
        let filePath = path.isEmpty ? "SKILL.md" : "\(path)/SKILL.md"
        return URL(string: "https://raw.githubusercontent.com/\(source)/\(branch)/\(filePath)")!
    }

    /// Build the GitHub Contents API URL for a SKILL.md file.
    ///
    /// URL pattern: `https://api.github.com/repos/{owner}/{repo}/contents/{path}/SKILL.md?ref={branch}`
    /// The API returns JSON with a base64-encoded `content` field, which is more resilient
    /// than relying solely on GitHub's raw CDN in restricted network environments.
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - path: Relative path to the skill directory
    ///   - branch: Git branch name ("main" or "master")
    /// - Returns: Fully constructed GitHub Contents API URL
    func buildContentsAPIURL(source: String, path: String, branch: String) -> URL {
        let filePath = path.isEmpty ? "SKILL.md" : "\(path)/SKILL.md"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/repos/\(source)/contents/\(filePath)"
        components.queryItems = [URLQueryItem(name: "ref", value: branch)]
        return components.url!
    }

    /// Generate all candidate raw URLs to try when fetching a skill's SKILL.md
    ///
    /// Exposed for tests and debug visibility. The actual fetch path now prefers raw CDN
    /// when available and automatically falls back to the GitHub Contents API when needed.
    ///
    /// - Parameters:
    ///   - source: Repository in "owner/repo" format
    ///   - skillId: Skill identifier (directory name)
    /// - Returns: Array of candidate raw URLs to try in order
    func candidateURLs(source: String, skillId: String) -> [URL] {
        // Generate all combinations: branch × path
        // `flatMap` + `map` produces the cartesian product (similar to a nested for-loop)
        // Result: 4 paths × 2 branches = 8 candidate URLs
        ["main", "master"].flatMap { branch in
            candidatePaths(skillId: skillId).map { path in
                buildRawURL(source: source, path: path, branch: branch)
            }
        }
    }

    /// Compute the cache key for a source/skillId pair
    ///
    /// Exposed as internal for unit tests to verify cache key format.
    func cacheKey(source: String, skillId: String) -> String {
        "\(source)/\(skillId)"
    }

    /// Supported repository layouts in priority order.
    private func candidatePaths(skillId: String) -> [String] {
        [
            skillId,                          // Flat layout: {skillId}/SKILL.md at repo root
            "skills/\(skillId)",              // Monorepo layout: skills/{skillId}/SKILL.md
            ".claude/skills/\(skillId)",      // Plugin-style: .claude/skills/{skillId}/SKILL.md
            "",                               // Root level: SKILL.md at repo root (no subdirectory)
        ]
    }

    /// Fetch `SKILL.md` from a known repo path.
    ///
    /// Default strategy:
    /// 1. Try GitHub raw CDN (`raw.githubusercontent.com`) for lower overhead.
    /// 2. If raw CDN has a transport / server issue, mark it unavailable and retry via
    ///    GitHub Contents API.
    /// 3. If raw CDN returns `404`, treat it as "path not found" and continue to the next candidate.
    private func fetchContentAtPath(source: String, path: String, branch: String) async throws -> String? {
        if shouldBypassRawCDN {
            return try await fetchFromContentsAPI(source: source, path: path, branch: branch)
        }

        do {
            return try await fetchFromRawURL(
                buildRawURL(source: source, path: path, branch: branch)
            )
        } catch let error as FetchError {
            switch error {
            case .networkError, .invalidResponse, .invalidEncoding:
                shouldBypassRawCDN = true
                return try await fetchFromContentsAPI(source: source, path: path, branch: branch)
            case .notFound:
                return nil
            }
        } catch {
            throw error
        }
    }

    // MARK: - Private Networking

    /// fallback 发现逻辑：通过 GitHub Git Tree API 查找真实的 `SKILL.md` 路径。
    ///
    /// 当 `skillId` 与 GitHub 上的实际目录名不一致时，direct URL lookup 会失败。
    /// 这时会回退到 Git Tree API，一次性拉取整个 repository 的文件树，再在其中查找所有 `SKILL.md`。
    ///
    /// 相比逐目录调用 Contents API，这种方式请求更少、层级更深，也更适合 desktop app 的使用模式。
    /// 当前策略是：先查 `main`，失败后再查 `master`；命中候选 `SKILL.md` 后，再校验 YAML 中的 `name:` 字段。
    private func discoverViaTreeAPI(source: String, skillId: String) async throws -> String? {
        // 同时尝试 `main` 和 `master` 两个 branch。
        for branch in ["main", "master"] {
            // 构造带 `recursive=1` 的 Git Tree API URL，一次性获取完整文件树。
            guard let apiURL = URL(
                string: "https://api.github.com/repos/\(source)/git/trees/\(branch)?recursive=1"
            ) else {
                continue
            }

            // 从 GitHub 拉取完整文件树。
            guard let treePaths = await fetchTreeAPIListing(apiURL) else {
                continue
            }

            // 过滤出所有以 `SKILL.md` 结尾的路径，这些就是候选文件。
            let skillMDPaths = treePaths.filter { $0.hasSuffix("SKILL.md") }

            // 逐个尝试候选 `SKILL.md`，并校验其 `name:` 是否与目标 skill 匹配。
            for path in skillMDPaths {
                // 去掉末尾的 `/SKILL.md`，得到所在目录路径；如果是根目录文件，则使用空字符串。
                let dirPath: String
                if path == "SKILL.md" {
                    dirPath = ""
                } else {
                    // `dropLast` 用来去掉结尾的 `/SKILL.md`。
                    dirPath = String(path.dropLast("/SKILL.md".count))
                }

                guard let content = try await fetchContentAtPath(
                    source: source,
                    path: dirPath,
                    branch: branch
                ) else {
                    continue
                }

                // 通过 YAML frontmatter 里的 `name:` 字段确认它是否属于目标 skill，
                // 避免在 multi-skill repo 中返回错误内容。
                if contentMatchesSkillId(content, skillId: skillId) {
                    return content
                }
            }
        }

        return nil
    }

    /// Fetch the full file tree from the GitHub Git Tree API
    ///
    /// Sends a GET request to the Tree API URL and parses the JSON response to extract
    /// all file paths from the `tree` array. Returns nil on any failure (network error,
    /// non-200 status, invalid JSON) — the caller treats this as "tree not available".
    ///
    /// The response JSON structure:
    /// ```json
    /// {
    ///   "sha": "abc123...",
    ///   "tree": [
    ///     {"path": "README.md", "type": "blob", ...},
    ///     {"path": "skills/my-skill/SKILL.md", "type": "blob", ...},
    ///     {"path": "skills", "type": "tree", ...}
    ///   ],
    ///   "truncated": false
    /// }
    /// ```
    ///
    /// We only extract `path` values where `type == "blob"` (files, not directories).
    ///
    /// - Parameter url: The GitHub Git Tree API URL to fetch
    /// - Returns: Array of file paths, or nil on failure
    private func fetchTreeAPIListing(_ url: URL) async -> [String]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // GitHub API requires a specific Accept header for JSON responses.
        // v3+json is the stable REST API version.
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        // User-Agent is required by GitHub API — requests without it may be rejected
        request.setValue("SkillsMaster", forHTTPHeaderField: "User-Agent")

        // Execute request — use `try?` to silently handle network errors
        // (we don't want a network error here to propagate as a FetchError)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // Parse JSON response and extract the `tree` array.
        // `JSONSerialization` is Foundation's JSON parser (similar to Java's org.json or Go's encoding/json).
        // We cast to [String: Any] (dictionary) since the Tree API returns an object, not an array.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else {
            return nil
        }

        // Extract file paths from tree entries (only blobs = files, skip tree = directories).
        // `compactMap` filters out nil values — similar to Java's Stream.filter().map() or
        // Go's slice filtering pattern.
        return tree.compactMap { entry -> String? in
            guard let type = entry["type"] as? String,
                  type == "blob",
                  let path = entry["path"] as? String else {
                return nil
            }
            return path
        }
    }

    /// Check if a SKILL.md content's `name:` field matches the expected skillId
    ///
    /// Searches the YAML frontmatter (between `---` delimiters) for a line matching
    /// `name: {skillId}` or `name: "{skillId}"`. This is a lightweight text check —
    /// we don't need to fully parse the YAML just to verify the name matches.
    ///
    /// - Parameters:
    ///   - content: Raw SKILL.md file content
    ///   - skillId: Expected skill name to match against
    /// - Returns: true if the content's name field matches the skillId
    private func contentMatchesSkillId(_ content: String, skillId: String) -> Bool {
        // Extract the YAML frontmatter section (between first and second "---")
        // to avoid false matches in the markdown body
        let lines = content.components(separatedBy: "\n")

        var inFrontmatter = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if !inFrontmatter {
                    inFrontmatter = true
                    continue
                } else {
                    // End of frontmatter — stop searching
                    break
                }
            }

            if inFrontmatter {
                // Match "name: skillId" or "name: "skillId"" (with optional quotes)
                // `hasPrefix` is a simple string check — no regex needed for this pattern
                if trimmed.hasPrefix("name:") {
                    let nameValue = trimmed
                        .dropFirst("name:".count)
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    return nameValue == skillId
                }
            }
        }

        return false
    }

    /// Fetch content from GitHub's Contents API, returning nil for 404 responses.
    ///
    /// GitHub returns a JSON object with base64-encoded `content`, so this helper
    /// decodes the body back into UTF-8 markdown text.
    private func fetchFromContentsAPI(source: String, path: String, branch: String) async throws -> String? {
        struct ContentsResponse: Decodable {
            let content: String
            let encoding: String
        }

        var request = URLRequest(url: buildContentsAPIURL(source: source, path: path, branch: branch))
        request.timeoutInterval = 15
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsMaster", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw FetchError.invalidResponse(httpResponse.statusCode)
        }

        let payload: ContentsResponse
        do {
            payload = try JSONDecoder().decode(ContentsResponse.self, from: data)
        } catch {
            throw FetchError.networkError("Invalid GitHub API response")
        }

        guard payload.encoding.caseInsensitiveCompare("base64") == .orderedSame else {
            throw FetchError.invalidEncoding
        }

        let normalizedContent = payload.content.replacingOccurrences(of: "\n", with: "")
        guard
            let decodedData = Data(
                base64Encoded: normalizedContent,
                options: [.ignoreUnknownCharacters]
            ),
            let content = String(data: decodedData, encoding: .utf8)
        else {
            throw FetchError.invalidEncoding
        }

        return content
    }

    /// Fetch content from a specific raw URL, returning nil for 404 responses
    ///
    /// Returns `nil` for HTTP 404 (not found) to support the main→master fallback strategy.
    /// Throws `FetchError` for network errors or unexpected HTTP status codes.
    ///
    /// - Parameter url: The URL to fetch content from
    /// - Returns: String content if successful, nil if 404
    /// - Throws: `FetchError` for network or encoding errors
    private func fetchFromRawURL(_ url: URL) async throws -> String? {
        // Create HTTP request with timeout
        // URLRequest is similar to Java's HttpURLConnection or Go's http.NewRequest
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Accept plain text — raw.githubusercontent.com returns plain text by default
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        // Execute async network request
        // URLSession.shared is the singleton HTTP client (similar to Go's http.DefaultClient)
        // `try await` suspends until the response arrives — non-blocking under the hood
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error.localizedDescription)
        }

        // Check HTTP status code
        // `as?` is a conditional type cast (similar to Java's instanceof + cast)
        // `guard let` unwraps the optional and continues; if nil, falls through to the else branch
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.networkError("Invalid response type")
        }

        // 404 = file not found on this branch — return nil to try next branch
        if httpResponse.statusCode == 404 {
            return nil
        }

        // Any other non-200 status is an unexpected error
        guard httpResponse.statusCode == 200 else {
            throw FetchError.invalidResponse(httpResponse.statusCode)
        }

        // Decode response body as UTF-8 string
        guard let content = String(data: data, encoding: .utf8) else {
            throw FetchError.invalidEncoding
        }

        return content
    }
}
