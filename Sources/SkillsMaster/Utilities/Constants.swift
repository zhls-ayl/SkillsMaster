import SwiftUI

/// Constants centralizes management of the app's global constants
/// Uses enum as a namespace because enums without cases cannot be instantiated
/// This is Swift's best practice for creating pure namespaces (similar to Java's private constructor + static fields)
enum Constants {

    /// Agent brand colors at the app level
    /// SwiftUI's Color is similar to Android's Color or CSS's color
    enum AgentColors {
        static func color(for agent: AgentType) -> Color {
            switch agent {
            case .claudeCode: Color(red: 0.91, green: 0.45, blue: 0.29)   // Coral #E8734A
            case .codex:      Color(red: 0.20, green: 0.78, blue: 0.35)   // Green
            case .geminiCLI:  Color(red: 0.26, green: 0.52, blue: 0.96)   // Blue
            case .githubCopilot: Color(red: 0.58, green: 0.34, blue: 0.92)   // Purple
            case .openCode:   Color(red: 0.0, green: 0.71, blue: 0.67)    // Teal #00B5AB
            case .antigravity: Color(red: 0.36, green: 0.42, blue: 0.75)  // Indigo #5C6BC0
            case .cursor:      Color(red: 0.06, green: 0.73, blue: 0.89)  // Cyan #10BAE3
            case .kiroCLI:        Color(red: 0.55, green: 0.24, blue: 0.85)  // Violet
            case .codeBuddy:   Color(red: 0.91, green: 0.30, blue: 0.60)  // Pink #E84D99
            case .openClaw:    Color(red: 0.85, green: 0.18, blue: 0.15)  // Red #D92E26 (lobster/crayfish theme)
            case .trae:        Color(red: 0.20, green: 0.94, blue: 0.55)  // Bright Green #32F08C
            case .hermes:      Color(red: 0.94, green: 0.45, blue: 0.15)  // Hermès Orange #F07326
            }
        }
    }

    /// Scope badge colors
    enum ScopeColors {
        static func color(for scope: SkillScope) -> Color {
            switch scope {
            case .unassigned:   .orange
            case .shared:       .blue
            case .agentLocal:   .secondary
            case .project:      .green
            }
        }
    }

    /// Shared skills directory path (SkillsMaster private canonical storage)
    /// 当前 canonical skills 目录。
    /// 之所以放在 `~/.skillsmaster/skills/`，是为了避免与部分 Agent 会直接读取的目录重叠。
    static let sharedSkillsPath = "~/.skillsmaster/skills"

    /// Private canonical lock file path managed by SkillsMaster itself.
    static let lockFilePath = "~/.skillsmaster/.skill-lock.json"

    /// Legacy Skills CLI lock file path kept only as an external import source.
    static let legacyLockFilePath = "~/.agents/.skill-lock.json"

    /// Directory where custom repositories are cloned: ~/.skillsmaster/repos/
    static let reposBasePath = "~/.skillsmaster/repos"

    /// Config file that stores the list of user-configured custom repositories
    static let skillReposConfigPath = "~/.skillsmaster/.skillsmaster-repos.json"

    /// Cache file for custom repository lightweight scan indexes
    static let repositoryScanCachePath = "~/.skillsmaster/.repository-scan-cache.json"

    /// Whether the fixed LocalSkill source should be shown in Settings / Sidebar.
    static let localSkillRepositoryEnabledKey = "localSkillRepositoryEnabled"

    /// UserDefaults key for app appearance preference.
    /// Stored as `AppThemeMode.rawValue` (`system` / `light` / `dark`).
    static let appThemeModeKey = "appThemeMode"

    /// UserDefaults key for app language preference.
    /// Stored as `AppLanguageMode.rawValue` (`system` / `en` / `zh-Hans`).
    static let appLanguageModeKey = "appLanguageMode"

    /// UserDefaults key for automatic inline translation in skill detail pages.
    static let autoTranslationEnabledKey = "autoTranslationEnabled"
    static let autoTranslationInstalledEnabledKey = "autoTranslationInstalledEnabled"
    static let autoTranslationSkillsShEnabledKey = "autoTranslationSkillsShEnabled"
    static let autoTranslationClawHubEnabledKey = "autoTranslationClawHubEnabled"
    static let autoTranslationSkillsHubEnabledKey = "autoTranslationSkillsHubEnabled"
    static let autoTranslationRepositoriesEnabledKey = "autoTranslationRepositoriesEnabled"
    static let autoTranslationAgentsEnabledKey = "autoTranslationAgentsEnabled"

    /// UserDefaults key prefix for per-Agent install mode preferences.
    static let agentInstallModeKeyPrefix = "agentInstallMode"

    /// UserDefaults key for the configured external editor app path.
    static let externalEditorAppPathKey = "externalEditorAppPath"

    /// UserDefaults key for the configured default terminal type.
    static let defaultTerminalAppKey = "defaultTerminalApp"

    /// UserDefaults key for the preferred terminal app bundle path.
    static let defaultTerminalAppPathKey = "defaultTerminalAppPath"
}
