import Foundation

/// ClawHub skill model for marketplace browsing.
///
/// This model keeps ClawHub-specific fields separate from `RegistrySkill`, because ClawHub's API
/// contract and metadata semantics differ from skills.sh.
struct ClawHubSkill: Identifiable, Hashable {
    /// Stable marketplace slug used by ClawHub APIs and URL routes.
    let slug: String
    /// Human-readable skill name.
    let displayName: String
    /// Short summary shown in list rows and headers.
    let summary: String
    /// Latest published version if available.
    let latestVersion: String?
    /// Marketplace download count.
    let downloads: Int
    /// Marketplace star count.
    let stars: Int
    /// Number of published versions.
    let versionCount: Int?
    /// Owner handle, e.g. `skills`.
    let ownerHandle: String?
    /// Optional owner display name.
    let ownerDisplayName: String?
    /// Unix timestamp in milliseconds.
    let updatedAtMilliseconds: Int64?

    var id: String { slug }

    var name: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slug : trimmed
    }

    var descriptionText: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No description provided." : trimmed
    }

    var browserURL: URL {
        URL(string: "https://clawhub.ai/skills/\(slug)")!
    }

    var formattedDownloads: String {
        Self.numberFormatter.string(from: NSNumber(value: downloads)) ?? "\(downloads)"
    }

    var formattedStars: String {
        Self.numberFormatter.string(from: NSNumber(value: stars)) ?? "\(stars)"
    }

    var formattedUpdatedDate: String? {
        guard let updatedAtMilliseconds else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(updatedAtMilliseconds) / 1000)
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

/// Extended detail metadata returned by ClawHub detail API.
struct ClawHubSkillDetail: Hashable {
    let skill: ClawHubSkill
    let latestVersion: String?
    let latestVersionCreatedAt: Int64?
    let latestChangelog: String?
    let license: String?
    let moderationVerdict: String?
    let moderationSummary: String?

    /// Preferred version string for installation actions.
    var installVersion: String? {
        latestVersion ?? skill.latestVersion
    }

    var formattedLatestVersionDate: String? {
        guard let latestVersionCreatedAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(latestVersionCreatedAt) / 1000)
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
