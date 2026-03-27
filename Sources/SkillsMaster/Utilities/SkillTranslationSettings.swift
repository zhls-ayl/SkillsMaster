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
        guard autoTranslationEnabled else { return false }
        guard let scope else { return false }
        return enabledScopes.contains(scope)
    }
}
