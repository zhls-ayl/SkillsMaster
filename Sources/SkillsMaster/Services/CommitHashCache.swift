import Foundation

/// `CommitHashCache` 是 SkillsMaster 私有的 commit hash cache service。
///
/// 这里有一个明确的设计决策：**不修改** `\.skill-lock.json` 的格式，
/// 避免把 SkillsMaster 私有状态混进 canonical lock file。
///
/// 因此，SkillsMaster 会把 commit hash 单独存到自己的 cache 文件中，
/// 让 lock file 继续只承载安装来源语义，而不承载额外的应用私有状态。
///
/// 由于多个流程可能同时读写 cache 文件，这里使用 `actor` 保证 thread safety。
actor CommitHashCache {

    // MARK: - Data Types

    /// cache 文件对应的 JSON 结构。
    private struct CacheFile: Codable {
        /// skill name → commit hash 的映射。
        var skills: [String: String]
        /// 手动关联 skill → repository 信息的映射。
        var linkedSkills: [String: LinkedSkillInfo]?
    }

    /// 手动关联到 GitHub repository 的 skill 信息。
    /// 当 skill 没有 `lockEntry` 时，会把关联信息保存在这里，方便后续合成展示信息。
    struct LinkedSkillInfo: Codable {
        /// Repository source identifier (e.g. "crossoverJie/skills")
        var source: String
        /// Source type (currently fixed to "github")
        var sourceType: String
        /// Full repository URL (e.g. "https://github.com/crossoverJie/skills.git")
        var sourceUrl: String
        /// Relative path of SKILL.md in the repository (e.g. "skills/auto-blog-cover/SKILL.md")
        var skillPath: String
        /// git tree hash of the skill folder (used for update detection)
        var skillFolderHash: String
        /// Link time (ISO 8601 format)
        var linkedAt: String
    }

    // MARK: - Properties

    /// Default path for the cache file: ~/.skillsmaster/.skillsmaster-cache.json
    /// Migrated from ~/.agents/ to ~/.skillsmaster/ to keep SkillsMaster private files separate.
    /// `static let` is a compile-time constant, similar to Java's static final
    static let defaultPath: URL = {
        let home = NSString(string: "~/.skillsmaster/.skillsmaster-cache.json").expandingTildeInPath
        return URL(fileURLWithPath: home)
    }()

    /// Current cache file path (can be overridden in tests)
    private let filePath: URL

    /// In-memory cache: skill name → commit hash
    /// Loaded from disk on first access, subsequent operations read/write memory directly, saved to disk on save()
    private var cache: [String: String] = [:]

    /// In-memory cache: skill name → manually linked repository info
    /// Used to store GitHub repository info for manually linked skills without a lockEntry
    private var linkedSkillsCache: [String: LinkedSkillInfo] = [:]

    /// Whether it has been loaded from disk (to avoid repeated reading)
    private var isLoaded = false

    // MARK: - Initialization

    init(filePath: URL = CommitHashCache.defaultPath) {
        self.filePath = filePath
    }

    // MARK: - Public Methods

    /// Get commit hash for a specific skill
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    /// - Returns: commit hash, or nil if not cached
    func getHash(for skillName: String) -> String? {
        ensureLoaded()
        return cache[skillName]
    }

    /// Set commit hash for a specific skill (writes to memory only, call save() to persist)
    ///
    /// - Parameters:
    ///   - skillName: Unique identifier of the skill (directory name)
    ///   - hash: Full commit hash (40-character SHA-1)
    func setHash(for skillName: String, hash: String) {
        ensureLoaded()
        cache[skillName] = hash
    }

    /// Remove commit hash for a specific skill (writes to memory only, call save() to persist)
    ///
    /// Used by legacy cleanup flows to purge stale private cache entries after the
    /// corresponding lock file record and on-disk artifacts have been removed.
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    func removeHash(for skillName: String) {
        ensureLoaded()
        cache.removeValue(forKey: skillName)
    }

    // MARK: - Linked Skills Methods (Manually Linked Repo Info)

    /// Get manually linked info for a specific skill
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    /// - Returns: LinkedSkillInfo, or nil if not linked
    func getLinkedInfo(for skillName: String) -> LinkedSkillInfo? {
        ensureLoaded()
        return linkedSkillsCache[skillName]
    }

    /// Set manually linked info for a specific skill (writes to memory only, call save() to persist)
    ///
    /// - Parameters:
    ///   - skillName: Unique identifier of the skill (directory name)
    ///   - info: Linked repository info
    func setLinkedInfo(for skillName: String, info: LinkedSkillInfo) {
        ensureLoaded()
        linkedSkillsCache[skillName] = info
    }

    /// Remove manually linked info for a specific skill (writes to memory only, call save() to persist)
    ///
    /// When a user formally writes to the lock file via updateSkill,
    /// the linked info in cache can be removed (no longer needed)
    ///
    /// - Parameter skillName: Unique identifier of the skill (directory name)
    func removeLinkedInfo(for skillName: String) {
        ensureLoaded()
        linkedSkillsCache.removeValue(forKey: skillName)
    }

    /// Get all manually linked skill infos
    ///
    /// Used in SkillManager.refresh() to iterate all linked infos,
    /// synthesizing LockEntry for skills without a lockEntry
    func getAllLinkedInfos() -> [String: LinkedSkillInfo] {
        ensureLoaded()
        return linkedSkillsCache
    }

    /// Write in-memory cache to disk
    ///
    /// Uses atomic write (.atomic) to ensure file is not corrupted by a crash mid-write:
    /// writes to a temporary file first, then renames to replace the original file upon success.
    /// Similar to the pattern of writing a .tmp file then os.Rename in Go.
    func save() throws {
        let cacheFile = CacheFile(
            skills: cache,
            linkedSkills: linkedSkillsCache.isEmpty ? nil : linkedSkillsCache
        )
        let encoder = JSONEncoder()
        // prettyPrinted formats the JSON output for human readability and debugging
        // sortedKeys ensures consistent output order, facilitating git diff checks
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cacheFile)

        // Ensure parent directory exists (~/.skillsmaster/)
        let parentDir = filePath.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try data.write(to: filePath, options: .atomic)
    }

    // MARK: - Private Methods

    /// Ensure cache is loaded from disk (lazy loading)
    ///
    /// Loads from disk on first call, subsequent calls use in-memory cache directly.
    /// If file doesn't exist or parse fails, use an empty dictionary (no error thrown, degrade gracefully).
    private func ensureLoaded() {
        guard !isLoaded else { return }
        isLoaded = true

        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath.path) else { return }

        do {
            let data = try Data(contentsOf: filePath)
            let cacheFile = try JSONDecoder().decode(CacheFile.self, from: data)
            cache = cacheFile.skills
            // Load linked info (may be nil, old format files lack this field)
            linkedSkillsCache = cacheFile.linkedSkills ?? [:]
        } catch {
            // Restart with empty cache if file is corrupted or format incompatible
            // No error thrown because cache loss doesn't affect core functionality, just needs backfill
            cache = [:]
            linkedSkillsCache = [:]
        }
    }
}
