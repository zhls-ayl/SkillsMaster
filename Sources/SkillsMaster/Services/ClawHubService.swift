import Foundation

/// ClawHub API service for browsing/searching/downloading skills.
actor ClawHubService {

    enum SkillSort: String, CaseIterable, Identifiable {
        case downloads
        case newest
        case updated
        case installs
        case stars
        case name

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .downloads: return "Downloads"
            case .newest: return "Newest"
            case .updated: return "Updated"
            case .installs: return "Installs"
            case .stars: return "Stars"
            case .name: return "Name"
            }
        }

        var defaultDirection: SortDirection {
            switch self {
            case .name:
                return .ascending
            default:
                return .descending
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
        struct RequestBody: Encodable, Equatable {
            let cursor: String?
            let numItems: Int
            let sort: String
            let dir: String
            let highlightedOnly: Bool
            let nonSuspiciousOnly: Bool
        }

        var sort: SkillSort = .downloads
        var direction: SortDirection = .descending
        var highlightedOnly = false
        var nonSuspiciousOnly = false
        var limit = 50
        var cursor: String?

        var requestBody: RequestBody {
            RequestBody(
                cursor: cursor,
                numItems: limit,
                sort: sort.rawValue,
                dir: direction.rawValue,
                highlightedOnly: highlightedOnly,
                nonSuspiciousOnly: nonSuspiciousOnly
            )
        }
    }

    struct BrowsePage: Equatable {
        let items: [ClawHubSkill]
        let nextCursor: String?
        let hasMore: Bool
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
    private let convexURL = URL(string: "https://wry-manatee-359.convex.cloud")!
    private let convexClientHeader = "npm-1.24.8"

    /// Response cache to reduce repeated requests and limit rate-limit hits.
    private var detailCache: [String: ClawHubSkillDetail] = [:]
    private var contentCache: [String: String] = [:]

    // MARK: - Public API

    func fetchSkills(options: BrowseOptions = BrowseOptions()) async throws -> BrowsePage {
        let response: BrowseResponse = try await sendConvexQuery(
            path: "skills:listPublicPageV4",
            arguments: options.requestBody
        )
        return BrowsePage(
            items: response.page.map { $0.toClawHubSkill() },
            nextCursor: response.nextCursor,
            hasMore: response.hasMore
        )
    }

    func searchSkills(query: String, limit: Int = 50) async throws -> [ClawHubSkill] {
        do {
            let response: ConvexSearchResponse = try await sendConvexAction(
                path: "search:searchSkills",
                arguments: SearchArguments(
                    query: query,
                    highlightedOnly: false,
                    nonSuspiciousOnly: false,
                    limit: limit
                )
            )
            return response.map { $0.toClawHubSkill() }
        } catch {
            let response: LegacySkillSearchResponse = try await sendJSONRequest(
                path: "/api/v1/search",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: "\(limit)")
                ]
            )
            return response.results.map { $0.toClawHubSkill() }
        }
    }

    func fetchSkillDetail(slug: String) async throws -> ClawHubSkillDetail {
        if let cached = detailCache[slug] {
            return cached
        }

        let response: SkillDetailResponse = try await sendConvexQuery(
            path: "skills:getBySlug",
            arguments: SlugArguments(slug: slug)
        )
        let detail = response.toClawHubSkillDetail(requestedSlug: slug)
        detailCache[slug] = detail
        return detail
    }

    func fetchSkillContent(slug: String) async throws -> String {
        if let cached = contentCache[slug] {
            return cached
        }

        let detail = try await fetchSkillDetail(slug: slug)
        guard let versionID = detail.latestVersionID else {
            throw ServiceError.invalidResponse(statusCode: 200, message: "ClawHub did not return a version identifier for SKILL.md.")
        }

        let response: ReadmeResponse = try await sendConvexAction(
            path: "skills:getReadme",
            arguments: ReadmeArguments(versionId: versionID)
        )
        let content = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
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

    // MARK: - REST helpers

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
        let request = try makeRESTRequest(path: path, queryItems: queryItems)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func makeRESTRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
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

    // MARK: - Convex helpers

    private func sendConvexQuery<Response: Decodable, Arguments: Encodable>(
        path: String,
        arguments: Arguments
    ) async throws -> Response {
        try await sendConvexRequest(
            endpoint: "/api/query",
            path: path,
            arguments: arguments
        )
    }

    private func sendConvexAction<Response: Decodable, Arguments: Encodable>(
        path: String,
        arguments: Arguments
    ) async throws -> Response {
        try await sendConvexRequest(
            endpoint: "/api/action",
            path: path,
            arguments: arguments
        )
    }

    private func sendConvexRequest<Response: Decodable, Arguments: Encodable>(
        endpoint: String,
        path: String,
        arguments: Arguments
    ) async throws -> Response {
        let body = try JSONEncoder().encode(
            ConvexRequestBody(path: path, args: [arguments])
        )
        let request = try makeConvexRequest(endpoint: endpoint, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let envelope = try JSONDecoder().decode(ConvexEnvelope<Response>.self, from: data)
        switch envelope.status {
        case "success":
            guard let value = envelope.value else {
                throw ServiceError.invalidResponse(statusCode: 200, message: "ClawHub returned an empty Convex payload.")
            }
            return value
        case "error":
            throw ServiceError.invalidResponse(
                statusCode: 200,
                message: sanitizeConvexErrorMessage(envelope.errorMessage ?? "Server Error")
            )
        default:
            throw ServiceError.invalidResponse(statusCode: 200, message: "ClawHub returned an invalid Convex status.")
        }
    }

    private func makeConvexRequest(endpoint: String, body: Data) throws -> URLRequest {
        let url = convexURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(convexClientHeader, forHTTPHeaderField: "Convex-Client")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SkillsMaster", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func sanitizeConvexErrorMessage(_ message: String) -> String {
        let patterns = [
            #"\[Request ID:[^\]]+\]\s*"#,
            #"^\s*Server Error Called by client\s*"#,
            #"^\s*ConvexError:\s*"#
        ]

        return patterns.reduce(message) { partialResult, pattern in
            partialResult.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
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
    struct ConvexRequestBody<Arguments: Encodable>: Encodable {
        let path: String
        let format = "convex_encoded_json"
        let args: [Arguments]
    }

    struct ConvexEnvelope<Value: Decodable>: Decodable {
        let status: String
        let value: Value?
        let errorMessage: String?
    }

    struct SlugArguments: Encodable {
        let slug: String
    }

    struct ReadmeArguments: Encodable {
        let versionId: String
    }

    struct SearchArguments: Encodable {
        let query: String
        let highlightedOnly: Bool
        let nonSuspiciousOnly: Bool
        let limit: Int
    }

    struct BrowseResponse: Decodable {
        let hasMore: Bool
        let nextCursor: String?
        let page: [BrowseItemDTO]
    }

    struct BrowseItemDTO: Decodable {
        let latestVersion: VersionDTO?
        let owner: OwnerDTO?
        let ownerHandle: String?
        let skill: SkillDTO

        func toClawHubSkill() -> ClawHubSkill {
            skill.toClawHubSkill(
                owner: owner,
                fallbackOwnerHandle: ownerHandle,
                latestVersion: latestVersion
            )
        }
    }

    struct SkillDetailResponse: Decodable {
        let latestVersion: VersionDTO?
        let moderationInfo: ModerationInfoDTO?
        let owner: OwnerDTO?
        let requestedSlug: String?
        let resolvedSlug: String?
        let skill: SkillDTO

        func toClawHubSkillDetail(requestedSlug: String) -> ClawHubSkillDetail {
            let skillModel = skill.toClawHubSkill(
                owner: owner,
                fallbackOwnerHandle: owner?.handle,
                latestVersion: latestVersion
            )

            return ClawHubSkillDetail(
                skill: skillModel,
                latestVersion: latestVersion?.version ?? skillModel.latestVersion,
                latestVersionID: latestVersion?.id,
                latestVersionCreatedAt: latestVersion?.createdAtMilliseconds,
                latestChangelog: latestVersion?.changelog,
                license: latestVersion?.parsed?.license,
                moderationVerdict: latestVersion?.llmAnalysis?.verdict ?? moderationInfo?.verdict,
                moderationSummary: latestVersion?.llmAnalysis?.summary ?? moderationInfo?.summary
            )
        }
    }

    struct ReadmeResponse: Decodable {
        let text: String
    }

    typealias ConvexSearchResponse = [ConvexSearchResultDTO]

    struct LegacySkillSearchResponse: Decodable {
        let results: [SearchResultDTO]
    }

    struct SkillDTO: Decodable {
        let displayName: String?
        let slug: String
        let stats: StatsDTO?
        let summary: String?
        let updatedAt: Double?

        func toClawHubSkill(
            owner: OwnerDTO?,
            fallbackOwnerHandle: String?,
            latestVersion: VersionDTO?
        ) -> ClawHubSkill {
            ClawHubSkill(
                slug: slug,
                displayName: displayName ?? slug,
                summary: summary ?? "",
                latestVersion: latestVersion?.version,
                downloads: stats?.downloadsInt ?? 0,
                stars: stats?.starsInt ?? 0,
                versionCount: stats?.versionsInt,
                ownerHandle: owner?.handle ?? fallbackOwnerHandle,
                ownerDisplayName: owner?.displayName ?? owner?.name,
                updatedAtMilliseconds: updatedAt.map(Int64.init)
            )
        }
    }

    struct SearchResultDTO: Decodable {
        let displayName: String?
        let slug: String
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

    struct ConvexSearchResultDTO: Decodable {
        let owner: OwnerDTO?
        let ownerHandle: String?
        let skill: SkillDTO
        let version: VersionDTO?

        func toClawHubSkill() -> ClawHubSkill {
            skill.toClawHubSkill(
                owner: owner,
                fallbackOwnerHandle: ownerHandle,
                latestVersion: version
            )
        }
    }

    struct StatsDTO: Decodable {
        let downloads: Double?
        let stars: Double?
        let versions: Double?

        var downloadsInt: Int? {
            downloads.map(Int.init)
        }

        var starsInt: Int? {
            stars.map(Int.init)
        }

        var versionsInt: Int? {
            versions.map(Int.init)
        }
    }

    struct VersionDTO: Decodable {
        let createdAt: Double?
        let id: String?
        let changelog: String?
        let llmAnalysis: LLMAnalysisDTO?
        let parsed: ParsedVersionDTO?
        let version: String?

        enum CodingKeys: String, CodingKey {
            case createdAt
            case id = "_id"
            case changelog
            case llmAnalysis
            case parsed
            case version
        }

        var createdAtMilliseconds: Int64? {
            createdAt.map(Int64.init)
        }
    }

    struct ParsedVersionDTO: Decodable {
        let license: String?
    }

    struct OwnerDTO: Decodable {
        let displayName: String?
        let handle: String?
        let name: String?
    }

    struct LLMAnalysisDTO: Decodable {
        let summary: String?
        let verdict: String?
    }

    struct ModerationInfoDTO: Decodable {
        let summary: String?
        let verdict: String?
    }
}
