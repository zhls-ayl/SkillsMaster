import Foundation

#if canImport(Translation)
import Translation
#endif

protocol TranslationPackAvailabilityChecking: Sendable {
    func englishToSimplifiedChinese() async -> TranslationPackAvailabilityChecker.Availability
}

struct TranslationPackAvailabilityChecker: TranslationPackAvailabilityChecking {
    enum Availability: Equatable {
        case installed
        case supportedButNotInstalled
        case unavailable
    }

    func englishToSimplifiedChinese() async -> Availability {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(macOS 26.0, *), TranslationPlatformSupport.canCheckLanguageAvailability {
            let availability = LanguageAvailability()
            let status = await availability.status(
                from: Locale.Language(identifier: "en"),
                to: Locale.Language(identifier: "zh-Hans")
            )

            switch status {
            case .installed:
                return .installed
            case .supported:
                return .supportedButNotInstalled
            case .unsupported:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        }
        #endif

        return .unavailable
    }
}
