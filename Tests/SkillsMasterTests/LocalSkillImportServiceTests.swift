import XCTest
@testable import SkillsMaster

final class LocalSkillImportServiceTests: XCTestCase {

    func testScanCandidatesForSingleSkillMarkdownRequiresCustomName() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-local-import-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let skillMDURL = tempDir.appendingPathComponent("SKILL.md")
        try """
        ---
        name: markdown-only
        description: single markdown import
        ---
        # Hello
        """.write(
            to: skillMDURL,
            atomically: true,
            encoding: .utf8
        )

        let service = LocalSkillImportService()
        let candidates = try await service.scanCandidates(at: skillMDURL, includeHiddenPaths: false)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].requiresCustomName)
        XCTAssertEqual(candidates[0].metadata.name, "markdown-only")
        XCTAssertEqual(candidates[0].sourceURL.path, skillMDURL.path)
    }

    func testScanCandidatesForDirectoryRecursivelyFindsRootAndNestedSkills() async throws {
        let fm = FileManager.default
        let rootDir = fm.temporaryDirectory.appendingPathComponent("SkillsMaster-local-import-\(UUID().uuidString)")
        let nestedDir = rootDir.appendingPathComponent("nested").appendingPathComponent("child-skill")
        try fm.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: rootDir) }

        try """
        ---
        name: root-skill
        description: root
        ---
        """.write(
            to: rootDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        name: child-skill
        description: child
        ---
        """.write(
            to: nestedDir.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = LocalSkillImportService()
        let candidates = try await service.scanCandidates(at: rootDir, includeHiddenPaths: false)

        XCTAssertEqual(candidates.map(\.suggestedSkillName), ["child-skill", "root-skill"])
        XCTAssertEqual(
            Set(candidates.map(\.sourceURL.lastPathComponent)),
            Set(["child-skill", rootDir.lastPathComponent])
        )
        XCTAssertTrue(candidates.allSatisfy { !$0.requiresCustomName })
    }
}
