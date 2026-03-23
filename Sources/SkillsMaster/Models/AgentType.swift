import Foundation

/// AgentType represents supported AI code assistant types
/// Similar to Java enum, but Swift enum is more powerful, supporting associated values and methods
enum AgentType: String, CaseIterable, Identifiable, Codable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case geminiCLI = "gemini-cli"
    case githubCopilot = "github-copilot"
    case openCode = "opencode"       // OpenCode: Open source AI programming CLI tool
    case antigravity = "antigravity"   // Antigravity: Google's AI coding agent (https://antigravity.google)
    case cursor = "cursor"               // Cursor: AI-powered code editor (https://cursor.com)
    case kiroCLI = "kiro-cli"                 // Kiro CLI: AWS AI IDE built on Code OSS (https://kiro.dev)
    case codeBuddy = "codebuddy"           // CodeBuddy: Tencent Cloud AI coding assistant (https://www.codebuddy.ai)
    case openClaw = "openclaw"             // OpenClaw: AI coding assistant with ClawHub registry (https://openclaw.ai)
    case trae = "trae"                       // Trae: ByteDance's AI IDE (https://trae.ai)

    // Identifiable protocol requirement (similar to Java's Comparable), needed for SwiftUI list rendering
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .githubCopilot: "GitHub Copilot"
        case .openCode: "OpenCode"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .kiroCLI: "Kiro CLI"
        case .codeBuddy: "CodeBuddy"
        case .openClaw: "OpenClaw"
        case .trae: "Trae"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "copilot-cli", "github-copilot":
            self = .githubCopilot
        case "kiro", "kiro-cli":
            self = .kiroCLI
        default:
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown AgentType raw value: \(rawValue)"
                )
            }
            self = value
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Color scheme for each Agent, used for UI distinction
    /// SwiftUI uses Color type, similar to Android's Color
    var brandColor: String {
        switch self {
        case .claudeCode: "coral"     // #E8734A
        case .codex: "green"
        case .geminiCLI: "blue"
        case .githubCopilot: "purple"
        case .openCode: "teal"
        case .antigravity: "indigo"
        case .cursor: "cyan"
        case .kiroCLI: "violet"
        case .codeBuddy: "pink"
        case .openClaw: "red"
        case .trae: "brightGreen"
        }
    }

    /// SF Symbol icon name corresponding to the Agent
    /// SF Symbols is Apple's system icon library, similar to Material Icons
    /// Used as fallback when bundled SVG icon cannot be loaded.
    var iconName: String {
        switch self {
        case .claudeCode: "brain.head.profile"
        case .codex: "terminal"
        case .geminiCLI: "sparkles"
        case .githubCopilot: "airplane"
        case .openCode: "chevron.left.forwardslash.chevron.right"  // </> Code symbol, fitting OpenCode's programming theme
        case .antigravity: "arrow.up.circle"  // Upward motion symbolizing anti-gravity
        case .cursor: "cursorarrow.rays"        // Cursor arrow icon matching the Cursor IDE brand
        case .kiroCLI: "k.circle"                   // Letter K icon for Kiro CLI
        case .codeBuddy: "c.circle"               // Letter C icon for CodeBuddy
        case .openClaw: "o.circle"               // Letter O icon for OpenClaw
        case .trae: "t.circle"                     // Letter T icon for Trae
        }
    }

    /// Bundled SVG icon resource name under Resources/AgentIcons/*.svg
    var iconResourceName: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCLI: "gemini"
        case .githubCopilot: "githubcopilot"
        case .openCode: "opencode"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .kiroCLI: "kiro"
        case .codeBuddy: "codebuddy"
        case .openClaw: "openclaw"
        case .trae: "trae"
        }
    }

    /// User-level skills directory path for the Agent
    /// ~ represents user home directory, e.g., /Users/chenjie
    var skillsDirectoryPath: String {
        switch self {
        case .claudeCode: "~/.claude/skills"
        case .codex: "~/.codex/skills"        // Codex-specific skills directory (also reads ~/.agents/skills/)
        case .geminiCLI: "~/.gemini/skills"
        case .githubCopilot: "~/.copilot/skills"
        case .openCode: "~/.config/opencode/skills"  // OpenCode uses XDG-style configuration path
        case .antigravity: "~/.gemini/antigravity/skills"  // Antigravity stores skills under Gemini's config directory
        case .cursor: "~/.cursor/skills"                    // Cursor IDE skills directory
        case .kiroCLI: "~/.kiro/skills"                       // Kiro CLI skills directory
        case .codeBuddy: "~/.codebuddy/skills"             // CodeBuddy AI assistant skills directory
        case .openClaw: "~/.openclaw/skills"               // OpenClaw AI assistant skills directory
        case .trae: "~/.trae/skills"                         // Trae AI IDE skills directory
        }
    }

    /// Resolved absolute path URL
    var skillsDirectoryURL: URL {
        let expanded = NSString(string: skillsDirectoryPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Configuration directory of the Agent
    var configDirectoryPath: String? {
        switch self {
        case .claudeCode: "~/.claude"
        case .codex: "~/.codex"                // Codex configuration directory
        case .geminiCLI: "~/.gemini"
        case .githubCopilot: "~/.copilot"
        case .openCode: "~/.config/opencode"
        case .antigravity: "~/.gemini/antigravity"
        case .cursor: "~/.cursor"
        case .kiroCLI: "~/.kiro"
        case .codeBuddy: "~/.codebuddy"
        case .openClaw: "~/.openclaw"
        case .trae: "~/.trae"
        }
    }

    /// Resolved absolute configuration directory URL
    var configDirectoryURL: URL? {
        guard let configDirectoryPath else { return nil }
        let expanded = NSString(string: configDirectoryPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// CLI command used to detect if the Agent is installed
    var detectCommand: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCLI: "gemini"
        case .githubCopilot: "gh"
        case .openCode: "opencode"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .kiroCLI: "kiro"
        case .codeBuddy: "codebuddy"
        case .openClaw: "openclaw"
        case .trae: "trae"
        }
    }

    /// SkillsMaster private canonical skills directory URL (~/.skillsmaster/skills/)
    /// Managed skill files are stored here; Agent directories contain symbolic links or synced physical copies.
    /// Migrated from ~/.agents/skills/ to avoid overlap with Agent-readable directories.
    static let sharedSkillsDirectoryURL: URL = {
        let path = NSString(string: "~/.skillsmaster/skills").expandingTildeInPath
        return URL(fileURLWithPath: path)
    }()

    /// Legacy shared skills directory (~/.agents/skills/) — still readable by Codex, Gemini CLI, OpenCode at runtime.
    /// Used by additionalReadableSkillsDirectories for inheritance detection and by MigrationManager
    /// to migrate existing data to the new canonical location.
    static let legacySharedSkillsDirectoryURL: URL = {
        let path = NSString(string: "~/.agents/skills").expandingTildeInPath
        return URL(fileURLWithPath: path)
    }()

    /// Agents sorted for UI display: shorter names first, then alphabetical order.
    /// This reduces visual jaggedness when labels are shown in a vertical list.
    static var displayNameLengthSortedCases: [AgentType] {
        allCases.sorted { lhs, rhs in
            if lhs.displayName.count != rhs.displayName.count {
                return lhs.displayName.count < rhs.displayName.count
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Skills directories of other Agents that this Agent can read in addition to its own skills directory
    ///
    /// This is the "Single Source of Truth" for cross-directory reading rules.
    /// These rules describe each Agent's runtime behavior (which directories it scans for skills).
    /// SkillsMaster uses this information for display only (inheritance hints) — it does NOT
    /// interfere with cross-reading by creating/removing symbolic links in other Agents' directories.
    ///
    /// sourceAgent is set to the current agent itself because the inheritance is that agent's
    /// own behavior, not controlled by another agent. This field is used for UI display only.
    ///
    /// Returns an array of tuples: (Directory URL, Source Agent Type)
    /// Similar to Java's Pair<URL, AgentType>, Swift uses named tuples for better clarity
    var additionalReadableSkillsDirectories: [(url: URL, sourceAgent: AgentType)] {
        switch self {
        case .codex:
            // Codex reads ~/.agents/skills/ as its project-level convention
            // See: https://developers.openai.com/codex/skills/#where-to-save-skills
            return [(Self.legacySharedSkillsDirectoryURL, .codex)]
        case .geminiCLI:
            // Gemini CLI reads ~/.agents/skills/ as a cross-agent compatibility alias
            // See: https://geminicli.com/docs/cli/skills/
            return [(Self.legacySharedSkillsDirectoryURL, .geminiCLI)]
        case .githubCopilot:
            // GitHub Copilot can also read Claude Code's skills directory
            // See: https://docs.github.com/en/copilot/concepts/agents/about-agent-skills
            return [(AgentType.claudeCode.skillsDirectoryURL, .githubCopilot)]
        case .openCode:
            // OpenCode can also read Claude Code's and the legacy shared skills directories
            // See: https://opencode.ai/docs/skills/#place-files
            return [
                (AgentType.claudeCode.skillsDirectoryURL, .openCode),
                (Self.legacySharedSkillsDirectoryURL, .openCode)
            ]
        case .cursor:
            // Cursor can also read Claude Code's skills directory
            // See: https://cursor.com/docs/context/skills
            return [(AgentType.claudeCode.skillsDirectoryURL, .cursor)]
        default:
            return []
        }
    }
}
