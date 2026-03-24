import Foundation

/// Abstraction for ClawHub API calls used by `ClawHubBrowserViewModel`.
///
/// Keeping this protocol small allows deterministic ViewModel tests without real network I/O.
protocol ClawHubServiceProtocol {
    func fetchSkills(options: ClawHubService.BrowseOptions) async throws -> ClawHubService.BrowsePage
    func searchSkills(query: String, limit: Int) async throws -> [ClawHubSkill]
    func fetchSkillDetail(slug: String) async throws -> ClawHubSkillDetail
    func fetchSkillContent(slug: String) async throws -> String
    func downloadSkillArchive(slug: String, version: String) async throws -> Data
}

/// Abstraction for SkillsHub API calls used by `SkillsHubBrowserViewModel`.
protocol SkillsHubServiceProtocol {
    func clearCache() async
    func fetchSkills(options: SkillsHubService.BrowseOptions) async throws -> SkillsHubService.BrowsePage
    func fetchFeaturedSkills() async throws -> [SkillsHubSkill]
    func searchSkills(query: String, limit: Int) async throws -> [SkillsHubSkill]
    func fetchSkill(slug: String) async throws -> SkillsHubSkill
    func fetchSkillDetail(slug: String, seed: SkillsHubSkill?) async throws -> SkillsHubSkillDetail
    func downloadSkillArchive(slug: String) async throws -> Data
}

/// Abstraction for skills.sh registry calls used by `RegistryBrowserViewModel`.
protocol SkillRegistryServiceProtocol {
    func search(query: String, limit: Int) async throws -> [RegistrySkill]
    func fetchLeaderboard(category: SkillRegistryService.LeaderboardCategory) async throws -> [RegistrySkill]
    func clearCache() async
}

extension ClawHubService: ClawHubServiceProtocol {}
extension SkillsHubService: SkillsHubServiceProtocol {}
extension SkillRegistryService: SkillRegistryServiceProtocol {}
