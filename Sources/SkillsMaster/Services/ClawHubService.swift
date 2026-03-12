import Foundation

/// ClawHub API service for browsing/searching/downloading skills.
actor ClawHubService {

    enum SkillSort: String, CaseIterable, Identifiable {
        case `default`
        case downloads
        case stars

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .default: return "Default"
            case .downloads: return "Downloads"
            case .stars: return "Stars"
            }
        }
    }

    enum SortDirection: String, CaseIterable, Identifiable {
        case descending = "desc"
        case ascending = "asc"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .descending: return "Desc"
            case .ascending: return "Asc"
            }
        }
    }

    struct BrowseOptions: Equatable {
        var sort: SkillSort = .default
        var direction: SortDirection = .descending
        var highlightedOnly = false
        var nonSuspiciousOnly = false
        var limit = 50

        var queryItems: [URLQueryItem] {
            var items = [URLQueryItem(name: "limit", value: "\(limit)")]

            if sort != .default {
                items.append(URLQueryItem(name: "sort", value: sort.rawValue))
                items.append(URLQueryItem(name: "dir", value: direction.rawValue))
            }

            if highlightedOnly {
                items.append(URLQueryItem(name: "highlighted", value: "true"))
            }

            if nonSuspiciousOnly {
                items.append(URLQueryItem(name: "nonSuspicious", value: "true"))
            }

            return items
        }
    }

    enum ServiceError: Error, LocalizedError {
        case invalidURL
        case invalidResponse(statusCode: Int, message: String)
        case rateLimited(retryAfterSeconds: Int?)
        case archiveUnavailable
        case emptySkillContent

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Failed to build a valid ClawHub request URL."
            case .invalidResponse(let statusCode, let message):
                if message.isEmpty {
                    return "ClawHub request failed with status code \(statusCode)."
                }
                return "ClawHub request failed (\(statusCode)): \(message)"
            case .rateLimited(let retryAfterSeconds):
                if let retryAfterSeconds {
                    return "ClawHub is temporarily rate limiting requests. Try again in about \(retryAfterSeconds) seconds."
                }
                return "ClawHub is temporarily rate limiting requests. Please try again later."
            case .archiveUnavailable:
                return "ClawHub did not return a downloadable skill archive."
            case .emptySkillContent:
                return "ClawHub returned an empty SKILL.md file."
            }
        }
    }

    private let baseURL = URL(string: "https://clawhub.ai")!

    /// Response cache to reduce repeated requests and limit rate-limit hits.
    private var detailCache: [String: ClawHubSkillDetail] = [:]
    private var contentCache: [String: String] = [:]

    // MARK: - Public API

    func fetchSkills(options: BrowseOptions = BrowseOptions()) async throws -> [ClawHubSkill] {
        let response: SkillListResponse = try await sendJSONRequest(
            path: "/api/v1/skills",
            queryItems: options.queryItems
        )
        return response.items.map { $0.toClawHubSkill(owner: nil) }
    }

    func searchSkills(query: String, limit: Int = 50) async throws -> [ClawHubSkill] {
        let response: SkillSearchResponse = try await sendJSONRequest(
            path: "/api/v1/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return response.results.map { $0.toClawHubSkill() }
    }

    func fetchSkillDetail(slug: String) async throws -> ClawHubSkillDetail {
        if let cached = detailCache[slug] {
            return cached
        }

        let response: SkillDetailResponse = try await sendJSONRequest(path: "/api/v1/skills/\(slug)")
        let detail = response.toClawHubSkillDetail()
        detailCache[slug] = detail
        return detail
    }

    func fetchSkillContent(slug: String) async throws -> String {
        if let cached = contentCache[slug] {
            return cached
        }

        let data = try await sendDataRequest(
            path: "/api/v1/skills/\(slug)/file",
            queryItems: [URLQueryItem(name: "path", value: "SKILL.md")]
        )

        guard let content = String(data: data, encoding: .utf8) else {
            throw ServiceError.invalidResponse(statusCode: 200, message: "ClawHub returned non-UTF8 SKILL.md content.")
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.emptySkillContent
        }

        contentCache[slug] = content
        return content
    }

    func downloadSkillArchive(slug: String, version: String) async throws -> Data {
        let data = try await sendDataRequest(
            path: "/api/v1/download",
            queryItems: [
                URLQueryItem(name: "slug", value: slug),
                URLQueryItem(name: "version", value: version)
            ]
        )

        guard !data.isEmpty else {
            throw ServiceError.archiveUnavailable
        }
        return data
    }

    // MARK: - Request helpers

    private func sendJSONRequest<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let data = try await sendDataRequest(path: path, queryItems: queryItems)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sendDataRequest(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        let request = try makeRequest(path: path, queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ServiceError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("SkillsMaster", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse(statusCode: -1, message: "ClawHub returned a non-HTTP response.")
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after").flatMap(Int.init)
            throw ServiceError.rateLimited(retryAfterSeconds: retryAfter)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ServiceError.invalidResponse(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

// MARK: - DTOs

private extension ClawHubService {
    struct SkillListResponse: Decodable {
        let items: [SkillSummaryDTO]
    }

    struct SkillSearchResponse: Decodable {
        let results: [SearchResultDTO]
    }

    struct SkillDetailResponse: Decodable {
        let skill: SkillSummaryDTO
        let latestVersion: VersionDTO?
        let owner: OwnerDTO?
        let moderation: ModerationDTO?

        func toClawHubSkillDetail() -> ClawHubSkillDetail {
            let skillModel = skill.toClawHubSkill(owner: owner)
            return ClawHubSkillDetail(
                skill: skillModel,
                latestVersion: latestVersion?.version ?? skillModel.latestVersion,
                latestVersionCreatedAt: latestVersion?.createdAt,
                latestChangelog: latestVersion?.changelog,
                license: latestVersion?.license,
                moderationVerdict: moderation?.verdict,
                moderationSummary: moderation?.summary
            )
        }
    }

    struct SkillSummaryDTO: Decodable {
        let slug: String
        let displayName: String?
        let summary: String?
        let stats: StatsDTO?
        let updatedAt: Int64?
        let latestVersion: VersionDTO?
        let tags: TagsDTO?

        func toClawHubSkill(owner: OwnerDTO?) -> ClawHubSkill {
            ClawHubSkill(
                slug: slug,
                displayName: displayName ?? slug,
                summary: summary ?? "",
                latestVersion: latestVersion?.version ?? tags?.latest,
                downloads: stats?.downloads ?? 0,
                stars: stats?.stars ?? 0,
                versionCount: stats?.versions,
                ownerHandle: owner?.handle,
                ownerDisplayName: owner?.displayName,
                updatedAtMilliseconds: updatedAt
            )
        }
    }

    struct SearchResultDTO: Decodable {
        let slug: String
        let displayName: String?
        let summary: String?
        let version: String?
        let updatedAt: Int64?

        func toClawHubSkill() -> ClawHubSkill {
            ClawHubSkill(
                slug: slug,
                displayName: displayName ?? slug,
                summary: summary ?? "",
                latestVersion: version,
                downloads: 0,
                stars: 0,
                versionCount: nil,
                ownerHandle: nil,
                ownerDisplayName: nil,
                updatedAtMilliseconds: updatedAt
            )
        }
    }

    struct StatsDTO: Decodable {
        let downloads: Int?
        let stars: Int?
        let versions: Int?
    }

    struct TagsDTO: Decodable {
        let latest: String?
    }

    struct VersionDTO: Decodable {
        let version: String?
        let createdAt: Int64?
        let changelog: String?
        let license: String?
    }

    struct OwnerDTO: Decodable {
        let handle: String?
        let displayName: String?
    }

    struct ModerationDTO: Decodable {
        let verdict: String?
        let summary: String?
    }
}
