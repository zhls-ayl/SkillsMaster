import Foundation

/// 扫描用户选择的本地文件/目录，并生成可导入的 skill 候选项。
///
/// 支持三种输入：
/// - 单个 `SKILL.md` 文件
/// - 单个 skill 目录（目录内存在 `SKILL.md`）
/// - 父目录（递归扫描其下及子目录中的所有 skill 目录）
actor LocalSkillImportService {

    enum ImportError: Error, LocalizedError {
        case invalidSelection(String)
        case missingSkillMarkdown(String)

        var errorDescription: String? {
            switch self {
            case .invalidSelection(let path):
                return "Unsupported import selection: \(path)"
            case .missingSkillMarkdown(let path):
                return "No SKILL.md found in: \(path)"
            }
        }
    }

    struct Candidate: Identifiable, Equatable {
        enum SourceKind: Equatable {
            case markdownFile
            case directory
        }

        let sourceKind: SourceKind
        let sourceURL: URL
        let skillMDURL: URL
        let suggestedSkillName: String
        let metadata: SkillMetadata

        var id: String {
            sourceURL.standardizedFileURL.path
        }

        var requiresCustomName: Bool {
            sourceKind == .markdownFile
        }
    }

    private let gitService = GitService()

    func scanCandidates(at selectionURL: URL, includeHiddenPaths: Bool) async throws -> [Candidate] {
        let standardizedURL = selectionURL.standardizedFileURL
        let values = try standardizedURL.resourceValues(forKeys: [.isDirectoryKey])

        if values.isDirectory == true {
            return try await scanDirectoryCandidates(at: standardizedURL, includeHiddenPaths: includeHiddenPaths)
        }

        guard standardizedURL.lastPathComponent == "SKILL.md" else {
            throw ImportError.invalidSelection(standardizedURL.path)
        }

        let parsed = try SkillMDParser.parse(fileURL: standardizedURL)
        return [
            Candidate(
                sourceKind: .markdownFile,
                sourceURL: standardizedURL,
                skillMDURL: standardizedURL,
                suggestedSkillName: parsed.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines),
                metadata: parsed.metadata
            )
        ]
    }

    private func scanDirectoryCandidates(at directoryURL: URL, includeHiddenPaths: Bool) async throws -> [Candidate] {
        let discovered = await gitService.scanSkillsInRepo(
            repoDir: directoryURL,
            includeHiddenPaths: includeHiddenPaths
        )

        guard !discovered.isEmpty else {
            throw ImportError.missingSkillMarkdown(directoryURL.path)
        }

        return discovered.map { skill in
            let sourceURL = GitService.skillDirectoryURL(in: directoryURL, folderPath: skill.folderPath)
            let skillMDURL = directoryURL.appendingPathComponent(skill.skillMDPath)
            return Candidate(
                sourceKind: .directory,
                sourceURL: sourceURL,
                skillMDURL: skillMDURL,
                suggestedSkillName: skill.id,
                metadata: skill.metadata
            )
        }
    }
}
