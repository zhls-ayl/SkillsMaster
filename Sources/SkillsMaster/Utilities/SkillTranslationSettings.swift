import Foundation

enum SkillTranslationScope: String, CaseIterable, Identifiable {
    case installed
    case skillsSh
    case clawHub
    case skillsHub
    case repositories
    case agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed:
            "Installed"
        case .skillsSh:
            "Skills.sh"
        case .clawHub:
            "ClawHub"
        case .skillsHub:
            "SkillsHub"
        case .repositories:
            "Repositories"
        case .agents:
            "Agents Skills"
        }
    }
}

enum TranslationSettingsPolicy {
    static func isEnabled(
        autoTranslationEnabled: Bool,
        scope: SkillTranslationScope?,
        enabledScopes: Set<SkillTranslationScope>
    ) -> Bool {
        isEnabled(
            autoTranslationEnabled: autoTranslationEnabled,
            manualTranslationEnabled: false,
            scope: scope,
            enabledScopes: enabledScopes
        )
    }

    static func isEnabled(
        autoTranslationEnabled: Bool,
        manualTranslationEnabled: Bool,
        scope: SkillTranslationScope?,
        enabledScopes: Set<SkillTranslationScope>
    ) -> Bool {
        guard let scope else { return false }
        if manualTranslationEnabled { return true }
        guard autoTranslationEnabled else { return false }
        return enabledScopes.contains(scope)
    }
}
