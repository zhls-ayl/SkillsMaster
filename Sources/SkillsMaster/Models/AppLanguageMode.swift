import Foundation

enum AppLanguageMode: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system:
            AppLocalization.string("System Default")
        case .english:
            AppLocalization.string("English")
        case .simplifiedChinese:
            AppLocalization.string("Simplified Chinese")
        }
    }

    var resolvedLocale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: Self.english.rawValue)
        case .simplifiedChinese:
            Locale(identifier: Self.simplifiedChinese.rawValue)
        }
    }
}
