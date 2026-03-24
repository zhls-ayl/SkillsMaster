import Foundation

/// SkillsHub 分类枚举，映射当前网站暴露的分类 key。
enum SkillsHubCategory: String, CaseIterable, Identifiable, Codable {
    case aiIntelligence = "ai-intelligence"
    case developerTools = "developer-tools"
    case productivity
    case dataAnalysis = "data-analysis"
    case contentCreation = "content-creation"
    case securityCompliance = "security-compliance"
    case communicationCollaboration = "communication-collaboration"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aiIntelligence:
            return "AI 智能"
        case .developerTools:
            return "开发工具"
        case .productivity:
            return "效率提升"
        case .dataAnalysis:
            return "数据分析"
        case .contentCreation:
            return "内容创作"
        case .securityCompliance:
            return "安全合规"
        case .communicationCollaboration:
            return "通讯协作"
        }
    }
}

/// SkillsHub 列表模型。
struct SkillsHubSkill: Identifiable, Hashable {
    let slug: String
    let displayName: String
    let summary: String
    let localizedSummary: String?
    let category: SkillsHubCategory?
    let downloads: Int
    let installs: Int
    let stars: Int
    let score: Double?
    let latestVersion: String?
    let homepageURLString: String?
    let ownerName: String?
    let updatedAtMilliseconds: Int64?
    let tags: [String]

    var id: String { slug }

    var name: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slug : trimmed
    }

    var descriptionText: String {
        let localized = localizedSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !localized.isEmpty {
            return localized
        }

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "暂无描述。" : trimmed
    }

    var homepageURL: URL? {
        guard let homepageURLString,
              let url = URL(string: homepageURLString),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    var formattedDownloads: String {
        Self.integerFormatter.string(from: NSNumber(value: downloads)) ?? "\(downloads)"
    }

    var formattedInstalls: String {
        Self.integerFormatter.string(from: NSNumber(value: installs)) ?? "\(installs)"
    }

    var formattedStars: String {
        Self.integerFormatter.string(from: NSNumber(value: stars)) ?? "\(stars)"
    }

    var formattedScore: String? {
        guard let score else { return nil }
        return Self.decimalFormatter.string(from: NSNumber(value: score))
    }

    var formattedUpdatedDate: String? {
        guard let updatedAtMilliseconds else { return nil }
        return Self.format(milliseconds: updatedAtMilliseconds)
    }

    var originSourceType: String? {
        guard let host = homepageURL?.host?.lowercased() else { return nil }
        if host == "clawhub.ai" || host.hasSuffix(".clawhub.ai") {
            return "clawhub"
        }
        return nil
    }

    var originSourceURL: String? {
        homepageURL?.absoluteString
    }

    var originSource: String? {
        guard let url = homepageURL else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard !components.isEmpty else { return nil }

        if components.count >= 2 {
            return "\(components[components.count - 2])/\(components[components.count - 1])"
        }
        return components.last
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func format(milliseconds: Int64) -> String? {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// SkillsHub archive 中 `_meta.json` 的补充 metadata。
struct SkillsHubArchiveMetadata: Codable, Hashable {
    let ownerID: String?
    let slug: String?
    let version: String?
    let publishedAtMilliseconds: Int64?

    enum CodingKeys: String, CodingKey {
        case ownerID = "ownerId"
        case slug
        case version
        case publishedAtMilliseconds = "publishedAt"
    }
}

/// SkillsHub 详情模型。
struct SkillsHubSkillDetail {
    let skill: SkillsHubSkill
    let content: SkillMDParser.ParseResult
    let archiveMetadata: SkillsHubArchiveMetadata?
    let extractedFiles: [String]

    var installVersion: String? {
        let archiveVersion = archiveMetadata?.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !archiveVersion.isEmpty {
            return archiveVersion
        }

        let listedVersion = skill.latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return listedVersion.isEmpty ? nil : listedVersion
    }

    var formattedPublishedDate: String? {
        guard let milliseconds = archiveMetadata?.publishedAtMilliseconds else { return nil }
        return SkillsHubSkill.format(milliseconds: milliseconds)
    }

    var originSourceType: String? { skill.originSourceType }
    var originSource: String? { skill.originSource }
    var originSourceURL: String? { skill.originSourceURL }
}
