import Foundation

enum TranslationPlatformSupport {
    static var canCheckLanguageAvailability: Bool {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif

        return false
    }

    static var canPerformInlineTranslation: Bool {
        #if canImport(Translation) && compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif

        return false
    }
}
