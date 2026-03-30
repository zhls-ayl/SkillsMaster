import Foundation

/// SkillsHub API service for browsing/searching/downloading skills.
actor SkillsHubService {

    enum SkillSort: String, CaseIterable, Identifiable {
        case score
        case downloads
        case stars
        case installs
        case name

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .score:
                return AppLocalization.string("Score")
            case .downloads:
                return AppLocalization.string("Downloads")
            case .stars:
                return AppLocalization.string("Stars")
            case .installs:
                return AppLocalization.string("Installs")
            case .name:
                return AppLocalization.string("Name")
            }
        }
    }

    enum SortDirection: String, CaseIterable, Identifiable {
        case descending = "desc"
        case ascending = "asc"

        var id: String { rawValue }
    }

    struct BrowseOptions: Equatable {
        var page = 1
        var pageSize = 24
        var sort: SkillSort = .score
        var direction: SortDirection = .descending
        var keyword: String?
        var category: SkillsHubCategory?
    }

    struct BrowsePage: Equatable {
        let items: [SkillsHubSkill]
        let total: Int
    }

    enum ServiceError: Error, LocalizedError {
        case invalidURL
        case invalidResponse(statusCode: Int, message: String)
        case skillNotFound(String)
        case invalidArchive(String)
        case emptySkillContent(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return AppLocalization.string("Failed to construct a valid SkillsHub request URL.")
            case .invalidResponse(let statusCode, let message):
                if message.isEmpty {
                    return AppLocalization.format("SkillsHub request failed with status code %d.", statusCode)
                }
                return AppLocalization.format("SkillsHub request failed (%d): %@", statusCode, message)
            case .skillNotFound(let slug):
                return AppLocalization.format("SkillsHub skill not found: %@", slug)
            case .invalidArchive(let slug):
                return AppLocalization.format("Invalid SkillsHub skill archive: %@", slug)
            case .emptySkillContent(let slug):
                return AppLocalization.format("The SkillsHub package does not contain a valid SKILL.md: %@", slug)
            }
        }
    }

    private let browseBaseURL = URL(string: "https://lightmake.site")!
    private let indexBaseURL = URL(string: "https://skillhub-1388575217.cos.ap-guangzhou.myqcloud.com")!
    private let userAgent = "SkillsMaster"

    private var featuredCache: [SkillsHubSkill]?
    private var detailCache: [String: SkillsHubSkillDetail] = [:]
    private var archiveCache: [String: Data] = [:]

    func clearCache() {
        featuredCache = nil
        detailCache.removeAll()
        archiveCache.removeAll()
    }

    func fetchSkills(options: BrowseOptions = BrowseOptions()) async throws -> BrowsePage {
        var components = URLComponents(url: browseBaseURL.appendingPathComponent("api/skills"), resolvingAgainstBaseURL: false)
        components?.queryItems = buildQueryItems(options)

        guard let url = components?.url else {
            throw ServiceError.invalidURL
        }

        let response: BrowseResponse = try await sendJSONRequest(url: url)
        guard response.code == 0 else {
            throw ServiceError.invalidResponse(statusCode: 200, message: response.message)
        }
        return BrowsePage(
            items: response.data.skills.map(\.skill),
            total: response.data.total
        )
    }

    func fetchFeaturedSkills() async throws -> [SkillsHubSkill] {
        if let featuredCache {
            return featuredCache
        }

        let url = browseBaseURL.appendingPathComponent("api/skills/top")
        let response: BrowseResponse = try await sendJSONRequest(url: url)
        guard response.code == 0 else {
            throw ServiceError.invalidResponse(statusCode: 200, message: response.message)
        }
        let skills = response.data.skills.map(\.skill)
        featuredCache = skills
        return skills
    }

    func searchSkills(query: String, limit: Int = 20) async throws -> [SkillsHubSkill] {
        guard var components = URLComponents(url: browseBaseURL.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(max(1, limit))")
        ]

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        let response: SearchResponse = try await sendJSONRequest(url: url)
        return response.results.map(\.skill)
    }

    func fetchSkill(slug: String) async throws -> SkillsHubSkill {
        let keywordPage = try await fetchSkills(
            options: BrowseOptions(
                page: 1,
                pageSize: 24,
                sort: .score,
                direction: .descending,
                keyword: slug,
                category: nil
            )
        )
        if let exact = keywordPage.items.first(where: { $0.slug == slug }) {
            return exact
        }

        let searchResults = try await searchSkills(query: slug, limit: 20)
        if let exact = searchResults.first(where: { $0.slug == slug }) {
            return exact
        }

        throw ServiceError.skillNotFound(slug)
    }

    func fetchSkillDetail(slug: String, seed: SkillsHubSkill? = nil) async throws -> SkillsHubSkillDetail {
        if let cached = detailCache[slug] {
            return cached
        }

        let skill = try await resolvedSkill(slug: slug, seed: seed)
        let archiveData = try await downloadSkillArchive(slug: slug)
        let detail = try buildDetail(skill: skill, archiveData: archiveData)
        detailCache[slug] = detail
        return detail
    }

    func downloadSkillArchive(slug: String) async throws -> Data {
        if let cached = archiveCache[slug] {
            return cached
        }

        guard var components = URLComponents(url: browseBaseURL.appendingPathComponent("api/v1/download"), resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "slug", value: slug)]

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        let request = makeRequest(url: url, accept: "application/zip, application/octet-stream")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        guard !data.isEmpty else {
            throw ServiceError.invalidArchive(slug)
        }

        archiveCache[slug] = data
        return data
    }

    // MARK: - Private Helpers

    private func buildQueryItems(_ options: BrowseOptions) -> [URLQueryItem] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(max(1, options.page))"),
            URLQueryItem(name: "pageSize", value: "\(max(1, options.pageSize))"),
            URLQueryItem(name: "sortBy", value: options.sort.rawValue),
            URLQueryItem(name: "order", value: options.direction.rawValue)
        ]

        if let keyword = options.keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
           !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }

        if let category = options.category {
            items.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        return items
    }

    private func resolvedSkill(slug: String, seed: SkillsHubSkill?) async throws -> SkillsHubSkill {
        if let seed, seed.slug == slug {
            return seed
        }
        return try await fetchSkill(slug: slug)
    }

    private func buildDetail(skill: SkillsHubSkill, archiveData: Data) throws -> SkillsHubSkillDetail {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-SkillsHub-\(UUID().uuidString)")
        let archiveURL = tempRoot.appendingPathComponent("\(skill.slug).zip")
        let extractedRoot = tempRoot.appendingPathComponent("extracted")

        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempRoot) }

        try archiveData.write(to: archiveURL)
        try fm.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
        try extractZipArchive(at: archiveURL, to: extractedRoot)

        guard let skillDir = try locateSkillDirectory(in: extractedRoot) else {
            throw ServiceError.invalidArchive(skill.slug)
        }

        let skillMDURL = skillDir.appendingPathComponent("SKILL.md")
        guard fm.fileExists(atPath: skillMDURL.path) else {
            throw ServiceError.emptySkillContent(skill.slug)
        }

        let rawContent = try String(contentsOf: skillMDURL, encoding: .utf8)
        let parsedContent: SkillMDParser.ParseResult
        do {
            parsedContent = try SkillMDParser.parse(content: rawContent)
        } catch {
            parsedContent = SkillMDParser.ParseResult(
                metadata: SkillMetadata(
                    name: skill.name,
                    description: skill.descriptionText,
                    metadata: SkillMetadata.MetadataExtra(
                        author: skill.ownerName,
                        version: skill.latestVersion
                    )
                ),
                frontmatterText: "",
                markdownBody: rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let archiveMetadata = try loadArchiveMetadata(from: skillDir)
        let extractedFiles = try enumerateFiles(in: skillDir)

        return SkillsHubSkillDetail(
            skill: skill,
            content: parsedContent,
            archiveMetadata: archiveMetadata,
            extractedFiles: extractedFiles
        )
    }

    private func loadArchiveMetadata(from skillDir: URL) throws -> SkillsHubArchiveMetadata? {
        let metadataURL = skillDir.appendingPathComponent("_meta.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }

        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode(SkillsHubArchiveMetadata.self, from: data)
    }

    private func enumerateFiles(in rootURL: URL) throws -> [String] {
        var paths: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return paths
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            paths.append(fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: ""))
        }
        return paths.sorted()
    }

    private func extractZipArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipProcess.arguments = ["-xk", archiveURL.path, destinationURL.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw ServiceError.invalidArchive(archiveURL.lastPathComponent)
        }
    }

    private func locateSkillDirectory(in rootURL: URL) throws -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: rootURL.appendingPathComponent("SKILL.md").path) {
            return rootURL
        }

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            if fm.fileExists(atPath: fileURL.appendingPathComponent("SKILL.md").path) {
                return fileURL
            }
        }

        return nil
    }

    private func sendJSONRequest<Response: Decodable>(url: URL) async throws -> Response {
        let request = makeRequest(url: url, accept: "application/json")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func makeRequest(url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse(statusCode: -1, message: AppLocalization.string("Received a non-HTTP response."))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.invalidResponse(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

private extension SkillsHubService {
    struct BrowseResponse: Decodable {
        struct DataPayload: Decodable {
            let skills: [SkillDTO]
            let total: Int
        }

        let code: Int
        let data: DataPayload
        let message: String
    }

    struct SearchResponse: Decodable {
        let results: [SearchSkillDTO]
    }

    struct SkillDTO: Decodable {
        let category: String?
        let description: String?
        let descriptionZh: String?
        let downloads: Int?
        let homepage: String?
        let installs: Int?
        let name: String?
        let ownerName: String?
        let score: Double?
        let slug: String
        let stars: Int?
        let tags: [String]?
        let updatedAt: Int64?
        let version: String?

        enum CodingKeys: String, CodingKey {
            case category
            case description
            case descriptionZh = "description_zh"
            case downloads
            case homepage
            case installs
            case name
            case ownerName
            case score
            case slug
            case stars
            case tags
            case updatedAt = "updated_at"
            case version
        }

        var skill: SkillsHubSkill {
            SkillsHubSkill(
                slug: slug,
                displayName: name ?? slug,
                summary: description ?? "",
                localizedSummary: descriptionZh,
                category: category.flatMap(SkillsHubCategory.init(rawValue:)),
                downloads: downloads ?? 0,
                installs: installs ?? 0,
                stars: stars ?? 0,
                score: score,
                latestVersion: version,
                homepageURLString: homepage,
                ownerName: ownerName,
                updatedAtMilliseconds: updatedAt,
                tags: tags ?? []
            )
        }
    }

    struct SearchSkillDTO: Decodable {
        let displayName: String?
        let slug: String
        let summary: String?
        let updatedAt: Int64?
        let version: String?

        var skill: SkillsHubSkill {
            SkillsHubSkill(
                slug: slug,
                displayName: displayName ?? slug,
                summary: summary ?? "",
                localizedSummary: nil,
                category: nil,
                downloads: 0,
                installs: 0,
                stars: 0,
                score: nil,
                latestVersion: version,
                homepageURLString: nil,
                ownerName: nil,
                updatedAtMilliseconds: updatedAt,
                tags: []
            )
        }
    }
}
