import Foundation
import ObjectiveC.runtime

enum AppLocalization {
    private final class LocalizedMainBundle: Bundle, @unchecked Sendable {
        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            let bundle = AppLocalization.currentBundle()
            let localized = bundle.localizedString(forKey: key, value: value, table: tableName)
            if localized != key || value != nil {
                return localized
            }
            return Bundle.module.localizedString(forKey: key, value: value, table: tableName)
        }
    }

    private static let bundleOverrideInstalled: Void = {
        object_setClass(Bundle.main, LocalizedMainBundle.self)
    }()

    static func installBundleOverride() {
        _ = bundleOverrideInstalled
    }

    static func currentLanguageMode(userDefaults: UserDefaults = .standard) -> AppLanguageMode {
        guard
            let rawValue = userDefaults.string(forKey: Constants.appLanguageModeKey),
            let mode = AppLanguageMode(rawValue: rawValue)
        else {
            return .system
        }
        return mode
    }

    static func currentLocale(userDefaults: UserDefaults = .standard) -> Locale {
        currentLanguageMode(userDefaults: userDefaults).resolvedLocale
    }

    static func currentBundle(userDefaults: UserDefaults = .standard) -> Bundle {
        let languageCandidates: [String] = {
            switch currentLanguageMode(userDefaults: userDefaults) {
            case .system:
                let preferred = Locale.preferredLanguages.flatMap(localizationCandidates(for:))
                return preferred + ["en"]
            case .english:
                return localizationCandidates(for: AppLanguageMode.english.rawValue)
            case .simplifiedChinese:
                return localizationCandidates(for: AppLanguageMode.simplifiedChinese.rawValue)
            }
        }()

        for candidate in languageCandidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return Bundle.module
    }

    static func string(_ value: String.LocalizationValue, userDefaults: UserDefaults = .standard) -> String {
        String(
            localized: value,
            bundle: currentBundle(userDefaults: userDefaults),
            locale: currentLocale(userDefaults: userDefaults)
        )
    }

    static func format(_ format: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let template = string(format)
        return String(format: template, locale: currentLocale(), arguments: arguments)
    }

    static func relativeDateTime(from date: Date, to referenceDate: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = currentLocale()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func absoluteDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = currentLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func localizationCandidates(for languageIdentifier: String) -> [String] {
        let normalized = languageIdentifier.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: normalized)
        let languageCode = locale.language.languageCode?.identifier
        let scriptCode = locale.language.script?.identifier

        var candidates: [String] = [normalized]

        if let languageCode, let scriptCode {
            candidates.append("\(languageCode)-\(scriptCode)")
        }
        if let languageCode {
            candidates.append(languageCode)
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
