import XCTest
@testable import SkillsMaster

/// GitService 的单元测试
///
/// 主要测试 URL 规范化逻辑（纯逻辑，不需要网络或 git）
/// 使用 XCTest 框架（类似 JUnit / Go 的 testing 包）
final class GitServiceTests: XCTestCase {

    // MARK: - normalizeRepoURL Tests

    /// 测试 "owner/repo" 格式的 URL 规范化
    /// 输入：vercel-labs/skills
    /// 预期：repoURL = "https://github.com/vercel-labs/skills.git", source = "vercel-labs/skills"
    func testNormalizeRepoURL_ownerSlashRepo() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("vercel-labs/skills")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试完整 HTTPS URL 的规范化
    /// 输入：https://github.com/vercel-labs/skills
    /// 预期：repoURL 添加 .git 后缀，source 提取 owner/repo
    func testNormalizeRepoURL_fullHTTPS() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("https://github.com/vercel-labs/skills")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试已带 .git 后缀的 URL
    /// 输入：https://github.com/vercel-labs/skills.git
    /// 预期：保持原样，source 去掉 .git 后缀
    func testNormalizeRepoURL_withDotGit() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("https://github.com/vercel-labs/skills.git")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试带末尾斜杠的 URL
    /// 输入：https://github.com/vercel-labs/skills/
    /// 预期：正确处理末尾斜杠
    func testNormalizeRepoURL_withTrailingSlash() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("https://github.com/vercel-labs/skills/")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试无效的 URL 输入
    /// 输入：空字符串、单个单词、多层路径
    /// 预期：抛出 invalidRepoURL 错误
    func testNormalizeRepoURL_invalid() {
        // 空字符串
        XCTAssertThrowsError(try GitService.normalizeRepoURL("")) { error in
            // 验证错误类型是 GitError.invalidRepoURL
            // `as?` 是 Swift 的类型安全转换（类似 Java 的 instanceof + 强转）
            guard case GitService.GitError.invalidRepoURL = error else {
                XCTFail("Expected invalidRepoURL error, got: \(error)")
                return
            }
        }

        // 单个单词（无 /）
        XCTAssertThrowsError(try GitService.normalizeRepoURL("justarepo")) { error in
            guard case GitService.GitError.invalidRepoURL = error else {
                XCTFail("Expected invalidRepoURL error, got: \(error)")
                return
            }
        }

        // 多层路径（超过 owner/repo）
        XCTAssertThrowsError(try GitService.normalizeRepoURL("a/b/c")) { error in
            guard case GitService.GitError.invalidRepoURL = error else {
                XCTFail("Expected invalidRepoURL error, got: \(error)")
                return
            }
        }
    }

    /// 测试带空格的输入（应自动 trim）
    func testNormalizeRepoURL_withWhitespace() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("  vercel-labs/skills  ")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    /// 测试 owner/repo.git 格式（owner/repo 带 .git 后缀）
    func testNormalizeRepoURL_ownerSlashRepoWithDotGit() throws {
        let (repoURL, source) = try GitService.normalizeRepoURL("vercel-labs/skills.git")

        XCTAssertEqual(repoURL, "https://github.com/vercel-labs/skills.git")
        XCTAssertEqual(source, "vercel-labs/skills")
    }

    func testFolderPathForRootSkillMDPathReturnsEmptyString() {
        XCTAssertEqual(GitService.folderPath(for: "SKILL.md"), "")
        XCTAssertEqual(GitService.folderPath(for: "skills/my-skill/SKILL.md"), "skills/my-skill")
    }

    func testSkillDirectoryURLForRootSkillKeepsRepositoryPath() {
        let repoDir = URL(fileURLWithPath: "/tmp/SkillsMaster-root-skill")
        let resolved = GitService.skillDirectoryURL(in: repoDir, folderPath: "")

        XCTAssertEqual(resolved.path, repoDir.path)
    }

    // MARK: - scanSkillsInRepo Tests

    /// 验证 root-level `SKILL.md` 会把 metadata.name 作为 skill id，
    /// 而不是误用临时 clone 目录名。
    func testScanSkillsInRepoUsesMetadataNameForRootLevelSkill() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-test-\(UUID().uuidString)")
        try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)

        try """
        ---
        name: web-content-fetcher
        description: A root-level skill
        ---
        # Root Skill
        """.write(
            to: repoDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fm.removeItem(at: repoDir) }

        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)

        XCTAssertEqual(skills.count, 1)
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.id, "web-content-fetcher")
        XCTAssertEqual(skill.folderPath, "")
        XCTAssertEqual(skill.skillMDPath, "SKILL.md")
        XCTAssertEqual(skill.metadata.name, "web-content-fetcher")
    }

    /// 验证 `scanSkillsInRepo` 能发现隐藏目录（如 `.claude/skills/`）里的 `SKILL.md`。
    func testScanSkillsInRepoFindsHiddenDirectorySkills() async throws {
        let fm = FileManager.default
        // 创建一个临时目录，模拟已 clone 的 repository。
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-test-\(UUID().uuidString)")
        // 模拟 `.claude/skills/my-skill/SKILL.md` 这类目录结构。
        let skillDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
            .appendingPathComponent("my-skill")
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

        // 写入一个最小可用的 `SKILL.md`，包含 YAML frontmatter。
        let skillMDContent = """
        ---
        name: my-skill
        description: A test skill in a hidden directory
        ---
        # My Skill
        Hello world
        """
        try skillMDContent.write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // 通过 `defer` 确保函数退出时自动清理。
        defer { try? fm.removeItem(at: repoDir) }

        // `GitService` 是 `actor`，因此这里需要通过 `await` 调用方法。
        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)

        // 预期只会找到 1 个 skill。
        XCTAssertEqual(skills.count, 1, "Expected 1 skill in hidden directory, found \(skills.count)")
        // 验证 skill metadata。
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.id, "my-skill")
        XCTAssertEqual(skill.folderPath, ".claude/skills/my-skill")
        XCTAssertEqual(skill.skillMDPath, ".claude/skills/my-skill/SKILL.md")
        XCTAssertEqual(skill.markdownBody, "")
    }

    /// 验证 `scanSkillsInRepo` 在扫描时会跳过 `.git` 目录。
    ///
    /// `.git` 目录体积大，而且不会包含真正的 skills，因此必须显式忽略。
    func testScanSkillsInRepoSkipsGitDirectory() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-test-\(UUID().uuidString)")

        // 在顶层创建一个真实 skill。
        let realSkillDir = repoDir.appendingPathComponent("my-real-skill")
        try fm.createDirectory(at: realSkillDir, withIntermediateDirectories: true)
        let realContent = """
        ---
        name: my-real-skill
        description: A legitimate skill
        ---
        # Real Skill
        """
        try realContent.write(
            to: realSkillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // 在 `.git/` 内创建一个假的 `SKILL.md`，它应该被忽略。
        let gitDir = repoDir.appendingPathComponent(".git")
        try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let fakeContent = """
        ---
        name: fake-git-skill
        description: Should be ignored
        ---
        # Fake
        """
        try fakeContent.write(
            to: gitDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fm.removeItem(at: repoDir) }

        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)

        // 最终只应找到真实 skill，而不包含 `.git/` 里的假文件。
        XCTAssertEqual(skills.count, 1, "Expected 1 skill (should skip .git), found \(skills.count)")
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.id, "my-real-skill")
        XCTAssertEqual(skill.markdownBody, "")
    }

    /// 验证当 `includeHiddenPaths` 关闭时，隐藏路径会被忽略。
    ///
    /// 这是 custom repository 浏览模式的默认行为，用于避免路径歧义。
    func testScanSkillsInRepoSkipsHiddenPathsWhenDisabled() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-test-\(UUID().uuidString)")

        let supportedHidden = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
            .appendingPathComponent("supported-skill")
        try fm.createDirectory(at: supportedHidden, withIntermediateDirectories: true)
        try """
        ---
        name: supported-skill
        description: valid hidden layout
        ---
        """.write(
            to: supportedHidden.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let unsupportedHidden = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("unsupported-skill")
        try fm.createDirectory(at: unsupportedHidden, withIntermediateDirectories: true)
        try """
        ---
        name: unsupported-skill
        description: should be ignored
        ---
        """.write(
            to: unsupportedHidden.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fm.removeItem(at: repoDir) }

        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir, includeHiddenPaths: false)

        XCTAssertEqual(skills.count, 0, "Hidden paths should be skipped when includeHiddenPaths=false")
    }

    /// 验证当隐藏路径和普通路径都包含同名 skill 目录时，去重逻辑会优先保留普通路径。
    func testScanSkillsInRepoDeduplicatesSameIDPreferringNonHiddenPath() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-test-\(UUID().uuidString)")

        let hiddenDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
            .appendingPathComponent("create-skills")
        try fm.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try """
        ---
        name: create-skills-hidden
        description: hidden duplicate
        ---
        """.write(
            to: hiddenDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let normalDir = repoDir
            .appendingPathComponent("skills")
            .appendingPathComponent("create-skills")
        try fm.createDirectory(at: normalDir, withIntermediateDirectories: true)
        try """
        ---
        name: create-skills-normal
        description: normal duplicate
        ---
        """.write(
            to: normalDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fm.removeItem(at: repoDir) }

        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)

        XCTAssertEqual(skills.count, 1, "Duplicate id entries should be collapsed")
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.id, "create-skills")
        XCTAssertEqual(skill.folderPath, "skills/create-skills")
    }
    /// 验证 repository 列表索引阶段不会预加载 markdown body，正文按需读取。
    func testLoadSkillContentReadsMarkdownBodyOnDemand() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-test-\(UUID().uuidString)")
        let skillDir = repoDir.appendingPathComponent("lazy-skill")
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let content = """
        ---
        name: lazy-skill
        description: lazily loaded content
        ---
        # Lazy Skill
        This markdown should only load on demand.
        """
        try content.write(
            to: skillDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        defer { try? fm.removeItem(at: repoDir) }

        let gitService = GitService()
        let skills = await gitService.scanSkillsInRepo(repoDir: repoDir)
        let skill = try XCTUnwrap(skills.first)
        XCTAssertEqual(skill.markdownBody, "")

        let parseResult = try await gitService.loadSkillContent(
            skillMDPath: skill.skillMDPath,
            in: repoDir
        )
        XCTAssertEqual(parseResult.metadata.name, "lazy-skill")
        XCTAssertEqual(parseResult.markdownBody, """
        # Lazy Skill
        This markdown should only load on demand.
        """.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 验证 git working tree 干净时不会误报 dirty。
    func testIsWorkingTreeDirtyReturnsFalseForCleanRepository() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-git-clean-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: repoDir) }

        try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try runGit(arguments: ["init"], in: repoDir)
        try runGit(arguments: ["config", "user.name", "SkillsMaster Tests"], in: repoDir)
        try runGit(arguments: ["config", "user.email", "tests@example.com"], in: repoDir)

        try "initial".write(
            to: repoDir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(arguments: ["add", "README.md"], in: repoDir)
        try runGit(arguments: ["commit", "-m", "Initial commit"], in: repoDir)

        let gitService = GitService()
        let isDirty = try await gitService.isWorkingTreeDirty(in: repoDir)
        XCTAssertFalse(isDirty)
    }

    /// 验证 tracked / untracked 改动都会让 custom repository 缓存失效。
    func testIsWorkingTreeDirtyReturnsTrueForTrackedAndUntrackedChanges() async throws {
        let fm = FileManager.default
        let repoDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-git-dirty-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: repoDir) }

        try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try runGit(arguments: ["init"], in: repoDir)
        try runGit(arguments: ["config", "user.name", "SkillsMaster Tests"], in: repoDir)
        try runGit(arguments: ["config", "user.email", "tests@example.com"], in: repoDir)

        let trackedFile = repoDir.appendingPathComponent("tracked.txt")
        try "v1".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(arguments: ["add", "tracked.txt"], in: repoDir)
        try runGit(arguments: ["commit", "-m", "Initial commit"], in: repoDir)

        let gitService = GitService()

        try "v2".write(to: trackedFile, atomically: true, encoding: .utf8)
        var isDirty = try await gitService.isWorkingTreeDirty(in: repoDir)
        XCTAssertTrue(isDirty)

        try runGit(arguments: ["checkout", "--", "tracked.txt"], in: repoDir)
        try "temp".write(
            to: repoDir.appendingPathComponent("untracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        isDirty = try await gitService.isWorkingTreeDirty(in: repoDir)
        XCTAssertTrue(isDirty)
    }

    private func runGit(arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try gitExecutablePathForTests())
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(message)")
            return
        }
    }

    private func gitExecutablePathForTests() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]

        for candidate in candidates where candidate != "/usr/bin/git" {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw XCTSkip(
            "No functional git binary found outside /usr/bin/git; skipping integration-style GitService tests."
        )
    }

}
