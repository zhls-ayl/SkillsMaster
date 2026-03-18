import XCTest
@testable import SkillsMaster

final class SkillRepositoryTests: XCTestCase {

    func testConvertSSHToHTTPS() {
        let input = "git@github.com:org/repo.git"
        let output = SkillRepository.convertRepoURL(input, to: .httpsToken)
        XCTAssertEqual(output, "https://github.com/org/repo.git")
    }

    func testConvertHTTPSToSSH() {
        let input = "https://gitlab.com/team/private-skills.git"
        let output = SkillRepository.convertRepoURL(input, to: .ssh)
        XCTAssertEqual(output, "git@gitlab.com:team/private-skills.git")
    }

    func testConvertKeepsEnterpriseHost() {
        let input = "https://git.example.com/group/skills.git"
        let output = SkillRepository.convertRepoURL(input, to: .ssh)
        XCTAssertEqual(output, "git@git.example.com:group/skills.git")
    }

    func testConvertInvalidURLReturnsOriginal() {
        let input = "owner/repo"
        let output = SkillRepository.convertRepoURL(input, to: .httpsToken)
        XCTAssertEqual(output, input)
    }

    func testDecodeSyncOnLaunchDefaultsToFalseWhenMissing() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "team-skills",
          "repoURL": "https://example.com/org/repo.git",
          "authType": "httpsToken",
          "platform": "github",
          "isEnabled": true,
          "localSlug": "org-repo"
        }
        """

        let data = Data(json.utf8)
        let repo = try JSONDecoder().decode(SkillRepository.self, from: data)
        XCTAssertFalse(repo.syncOnLaunch)
    }

    func testDecodeSyncOnLaunchTrueWhenPresent() throws {
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "team-skills",
          "repoURL": "https://example.com/org/repo.git",
          "authType": "httpsToken",
          "platform": "github",
          "isEnabled": true,
          "localSlug": "org-repo",
          "syncOnLaunch": true
        }
        """

        let data = Data(json.utf8)
        let repo = try JSONDecoder().decode(SkillRepository.self, from: data)
        XCTAssertTrue(repo.syncOnLaunch)
    }

    func testDecodeFallsBackToDerivedLocalSlugWhenMissing() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "team-skills",
          "repoURL": "https://example.com/org/repo.git",
          "authType": "httpsToken",
          "platform": "github",
          "isEnabled": true
        }
        """

        let data = Data(json.utf8)
        let repo = try JSONDecoder().decode(SkillRepository.self, from: data)

        XCTAssertEqual(repo.localSlug, "org-repo")
        XCTAssertTrue(repo.localPath.hasSuffix("/repos/org-repo"))
    }

    func testDecodeRepairsEmptyLocalSlug() throws {
        let json = """
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "name": "team-skills",
          "repoURL": "https://example.com/org/repo.git",
          "authType": "httpsToken",
          "platform": "github",
          "isEnabled": true,
          "localSlug": ""
        }
        """

        let data = Data(json.utf8)
        let repo = try JSONDecoder().decode(SkillRepository.self, from: data)

        XCTAssertEqual(repo.localSlug, "org-repo")
        XCTAssertTrue(repo.localPath.hasSuffix("/repos/org-repo"))
    }

    func testLocalPathFallsBackWhenLocalSlugIsEmpty() {
        let repo = SkillRepository(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "repo",
            repoURL: "https://example.com/org/repo.git",
            authType: .httpsToken,
            platform: .github,
            isEnabled: true,
            lastSyncedAt: nil,
            localSlug: "",
            httpUsername: nil,
            credentialKey: nil,
            scanHiddenPaths: false,
            syncOnLaunch: false
        )

        XCTAssertEqual(repo.normalizedLocalSlug, "org-repo")
        XCTAssertTrue(repo.localPath.hasSuffix("/repos/org-repo"))
        XCTAssertFalse(repo.localPath.hasSuffix("/repos/"))
    }

    func testEffectiveLastSyncedAtUsesPersistedValue() {
        let persisted = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = SkillRepository(
            id: UUID(),
            name: "repo",
            repoURL: "https://example.com/org/repo.git",
            authType: .httpsToken,
            platform: .github,
            isEnabled: true,
            lastSyncedAt: persisted,
            localSlug: "non-existent-\(UUID().uuidString)",
            httpUsername: nil,
            credentialKey: nil,
            scanHiddenPaths: false,
            syncOnLaunch: false
        )

        XCTAssertEqual(repo.effectiveLastSyncedAt, persisted)
    }

    func testEffectiveLastSyncedAtIsNilWhenNoPersistedValueAndNotCloned() {
        let repo = SkillRepository(
            id: UUID(),
            name: "repo",
            repoURL: "https://example.com/org/repo.git",
            authType: .httpsToken,
            platform: .github,
            isEnabled: true,
            lastSyncedAt: nil,
            localSlug: "non-existent-\(UUID().uuidString)",
            httpUsername: nil,
            credentialKey: nil,
            scanHiddenPaths: false,
            syncOnLaunch: false
        )

        XCTAssertNil(repo.effectiveLastSyncedAt)
    }
}
