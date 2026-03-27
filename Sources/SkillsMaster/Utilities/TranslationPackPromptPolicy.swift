enum TranslationPackPromptPolicy {
    static func shouldShowPrompt(
        translationEnabledOnThisScreen: Bool,
        dontShowAgain: Bool,
        hasShownThisLaunch: Bool
    ) -> Bool {
        guard translationEnabledOnThisScreen else { return false }
        guard !dontShowAgain else { return false }
        guard !hasShownThisLaunch else { return false }
        return true
    }
}
