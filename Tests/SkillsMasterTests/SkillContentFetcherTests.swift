import XCTest
@testable import SkillsMaster

/// `SkillContentFetcher` 的单元测试。
///
/// 这些测试只验证纯逻辑部分，例如 URL 构造、candidate URL 生成和 cache key 规则，
/// 不会真的发起 network request。
///
/// 依赖网络结果的行为（例如 fetch 成功 / 失败、branch fallback）更适合放到 integration test
/// 或通过 mock 注入验证，而这对当前 `actor` 结构来说成本更高。
///
/// 测试框架使用 `XCTest`，测试方法必须以 `test` 开头，并通过 `XCTAssert*` 系列断言验证结果。
final class SkillContentFetcherTests: XCTestCase {

    // MARK: - URL Construction Tests

    /// 验证 flat layout + `main` branch 下 raw GitHub URL 的构造结果是否正确。
    func testBuildRawURLFlatLayout() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "vercel-labs/agent-skills",
            path: "vercel-react-best-practices",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/vercel-labs/agent-skills/main/vercel-react-best-practices/SKILL.md"
        )
    }

    /// 验证 monorepo layout（`skills/` 子目录）下的 URL 构造。
    func testBuildRawURLMonorepoLayout() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "inference-sh/skills",
            path: "skills/remotion-render",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/inference-sh/skills/main/skills/remotion-render/SKILL.md"
        )
    }

    /// 验证 `master` branch fallback 场景下的 URL 构造。
    func testBuildRawURLMasterBranch() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "some-user/some-repo",
            path: "my-skill",
            branch: "master"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/some-user/some-repo/master/my-skill/SKILL.md"
        )
    }

    /// 验证当 repo 名包含连字符或点号时，URL 构造仍能保留这些字符。
    func testBuildRawURLWithHyphensAndDots() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "my-org/my.repo-name",
            path: "skill-with-hyphens",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/my-org/my.repo-name/main/skill-with-hyphens/SKILL.md"
        )
    }

    /// 验证 monorepo layout 下 GitHub Contents API URL 的构造。
    ///
    /// 当 raw CDN 不可达时，fetcher 会改走 `api.github.com/repos/.../contents/...`
    /// 读取 base64 编码的文件内容。
    func testBuildContentsAPIURLMonorepoLayout() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildContentsAPIURL(
            source: "inference-sh/skills",
            path: "skills/remotion-render",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://api.github.com/repos/inference-sh/skills/contents/skills/remotion-render/SKILL.md?ref=main"
        )
    }

    /// 验证 root-level `SKILL.md` 的 GitHub Contents API URL 不会出现多余斜杠。
    func testBuildContentsAPIURLEmptyPath() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildContentsAPIURL(
            source: "some-user/some-repo",
            path: "",
            branch: "master"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://api.github.com/repos/some-user/some-repo/contents/SKILL.md?ref=master"
        )
        XCTAssertFalse(url.absoluteString.contains("/contents//SKILL.md"))
    }

    // MARK: - Candidate URL Tests

    /// 验证 `candidateURLs` 会按预期顺序生成全部 8 个候选 URL。
    func testCandidateURLsGeneratesAllCombinations() async {
        let fetcher = SkillContentFetcher()
        let urls = await fetcher.candidateURLs(
            source: "inference-sh/skills",
            skillId: "remotion-render"
        )

        // Should produce exactly 8 candidate URLs (2 branches × 4 layouts)
        XCTAssertEqual(urls.count, 8)

        let urlStrings = urls.map(\.absoluteString)

        // 1. main branch, flat layout
        XCTAssertEqual(
            urlStrings[0],
            "https://raw.githubusercontent.com/inference-sh/skills/main/remotion-render/SKILL.md"
        )
        // 2. main branch, monorepo layout (skills/ subdirectory)
        XCTAssertEqual(
            urlStrings[1],
            "https://raw.githubusercontent.com/inference-sh/skills/main/skills/remotion-render/SKILL.md"
        )
        // 3. main branch, plugin-style layout (.claude/skills/ subdirectory)
        XCTAssertEqual(
            urlStrings[2],
            "https://raw.githubusercontent.com/inference-sh/skills/main/.claude/skills/remotion-render/SKILL.md"
        )
        // 4. main branch, root layout (SKILL.md at repo root)
        XCTAssertEqual(
            urlStrings[3],
            "https://raw.githubusercontent.com/inference-sh/skills/main/SKILL.md"
        )
        // 5. master branch, flat layout
        XCTAssertEqual(
            urlStrings[4],
            "https://raw.githubusercontent.com/inference-sh/skills/master/remotion-render/SKILL.md"
        )
        // 6. master branch, monorepo layout
        XCTAssertEqual(
            urlStrings[5],
            "https://raw.githubusercontent.com/inference-sh/skills/master/skills/remotion-render/SKILL.md"
        )
        // 7. master branch, plugin-style layout
        XCTAssertEqual(
            urlStrings[6],
            "https://raw.githubusercontent.com/inference-sh/skills/master/.claude/skills/remotion-render/SKILL.md"
        )
        // 8. master branch, root layout
        XCTAssertEqual(
            urlStrings[7],
            "https://raw.githubusercontent.com/inference-sh/skills/master/SKILL.md"
        )
    }

    /// Test candidate URLs for a repo that uses flat layout
    ///
    /// Even for flat-layout repos, all 8 URLs are generated — the fetcher
    /// tries them in order and stops on the first 200 response.
    func testCandidateURLsFlatLayoutRepo() async {
        let fetcher = SkillContentFetcher()
        let urls = await fetcher.candidateURLs(
            source: "vercel-labs/agent-skills",
            skillId: "vercel-react-best-practices"
        )

        XCTAssertEqual(urls.count, 8)
        // First URL should be the flat layout on main (most likely to succeed)
        XCTAssertTrue(
            urls[0].absoluteString.contains("/main/vercel-react-best-practices/SKILL.md")
        )
    }

    /// Test that buildRawURL handles empty path correctly (root-level SKILL.md)
    ///
    /// When path is empty, the URL should be `/{branch}/SKILL.md` without a double slash.
    /// This covers single-skill repos that place SKILL.md directly at the repository root.
    func testBuildRawURLEmptyPath() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "some-user/some-repo",
            path: "",
            branch: "main"
        )

        // Should NOT contain a double slash before SKILL.md
        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/some-user/some-repo/main/SKILL.md"
        )
        XCTAssertFalse(url.absoluteString.contains("//SKILL.md"))
    }

    /// Test URL construction for plugin-style layout (.claude/skills/ subdirectory)
    ///
    /// Some repos like `nextlevelbuilder/ui-ux-pro-max-skill` store SKILL.md at
    /// `.claude/skills/{skillId}/SKILL.md`.
    func testBuildRawURLPluginStylePath() async {
        let fetcher = SkillContentFetcher()
        let url = await fetcher.buildRawURL(
            source: "nextlevelbuilder/ui-ux-pro-max-skill",
            path: ".claude/skills/ui-ux-pro-max",
            branch: "main"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://raw.githubusercontent.com/nextlevelbuilder/ui-ux-pro-max-skill/main/.claude/skills/ui-ux-pro-max/SKILL.md"
        )
    }

    /// Test that candidate URLs maintain the correct priority order
    ///
    /// Flat and monorepo layouts should come before plugin-style and root layouts,
    /// since they are the most common patterns. This ensures the fast path is tried first.
    func testCandidateURLsOrderPriority() async {
        let fetcher = SkillContentFetcher()
        let urls = await fetcher.candidateURLs(
            source: "owner/repo",
            skillId: "my-skill"
        )

        let urlStrings = urls.map(\.absoluteString)

        // Flat layout (most common) should be first
        XCTAssertTrue(urlStrings[0].contains("/main/my-skill/SKILL.md"))
        // Monorepo layout should be second
        XCTAssertTrue(urlStrings[1].contains("/main/skills/my-skill/SKILL.md"))
        // Plugin-style layout should be third
        XCTAssertTrue(urlStrings[2].contains("/main/.claude/skills/my-skill/SKILL.md"))
        // Root layout should be fourth
        XCTAssertTrue(urlStrings[3].hasSuffix("/main/SKILL.md"))
        // Then the same order repeats for master branch
        XCTAssertTrue(urlStrings[4].contains("/master/my-skill/SKILL.md"))
        XCTAssertTrue(urlStrings[5].contains("/master/skills/my-skill/SKILL.md"))
        XCTAssertTrue(urlStrings[6].contains("/master/.claude/skills/my-skill/SKILL.md"))
        XCTAssertTrue(urlStrings[7].hasSuffix("/master/SKILL.md"))
    }

    // MARK: - Cache Key Tests

    /// Test that the cache key is constructed as "{source}/{skillId}"
    ///
    /// The cache key must be unique per skill to prevent cache collisions.
    /// Using "source/skillId" as the key ensures skills from different repos don't collide.
    func testCacheKeyFormat() async {
        let fetcher = SkillContentFetcher()
        let key = await fetcher.cacheKey(
            source: "vercel-labs/agent-skills",
            skillId: "vercel-react-best-practices"
        )

        XCTAssertEqual(key, "vercel-labs/agent-skills/vercel-react-best-practices")
    }

    /// Test that different skills produce different cache keys
    func testCacheKeyUniqueness() async {
        let fetcher = SkillContentFetcher()

        let key1 = await fetcher.cacheKey(source: "org/repo", skillId: "skill-a")
        let key2 = await fetcher.cacheKey(source: "org/repo", skillId: "skill-b")
        let key3 = await fetcher.cacheKey(source: "other-org/repo", skillId: "skill-a")

        // Same repo, different skills → different keys
        XCTAssertNotEqual(key1, key2)
        // Same skill name, different repos → different keys
        XCTAssertNotEqual(key1, key3)
    }

    /// Test that cache clearing works without error
    ///
    /// After clearing the cache, subsequent fetches should hit the network (not cache).
    /// We can't directly verify cache emptiness from outside the actor,
    /// but we ensure the method doesn't throw or crash.
    func testClearCacheDoesNotThrow() async {
        let fetcher = SkillContentFetcher()
        // Should not throw or crash even when cache is already empty
        await fetcher.clearCache()
    }

    // MARK: - Error Type Tests

    /// Test that FetchError provides meaningful localized descriptions
    ///
    /// `LocalizedError` protocol's `errorDescription` is what users see in error messages.
    /// We verify each error case produces a non-nil, descriptive string.
    func testFetchErrorDescriptions() {
        let networkError = SkillContentFetcher.FetchError.networkError("timeout")
        XCTAssertTrue(networkError.localizedDescription.contains("timeout"))

        let notFound = SkillContentFetcher.FetchError.notFound
        XCTAssertTrue(notFound.localizedDescription.contains("not found"))

        let invalidResponse = SkillContentFetcher.FetchError.invalidResponse(500)
        XCTAssertTrue(invalidResponse.localizedDescription.contains("500"))

        let invalidEncoding = SkillContentFetcher.FetchError.invalidEncoding
        XCTAssertTrue(invalidEncoding.localizedDescription.contains("UTF-8"))
    }
}
