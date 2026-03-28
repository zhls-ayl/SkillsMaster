import SwiftUI

/// AppThemeMode represents the app-level appearance preference selected by the user.
///
/// Why this enum exists:
/// - We need a single source of truth for the three supported options: System / Light / Dark.
/// - Using `String` raw values makes persistence in UserDefaults straightforward and stable.
/// - Centralizing label text and `ColorScheme` mapping avoids duplicated switch statements
///   across App and Settings views.
///
/// Compared with Java/Go/Python:
/// - Similar to a Java enum with fields/getters.
/// - More expressive than ad-hoc string constants (reduces invalid-state bugs).
enum AppThemeMode: String, CaseIterable, Identifiable {
    /// Follow macOS appearance (light/dark) automatically.
    case system
    /// Force light appearance.
    case light
    /// Force dark appearance.
    case dark

    /// Identifiable conformance allows direct use in SwiftUI `ForEach`.
    /// Returning `self` is safe because enum cases are unique and stable identifiers.
    var id: Self { self }

    /// User-facing label shown in Settings picker.
    /// Keeping labels here ensures UI text stays consistent everywhere.
    var displayName: String {
        switch self {
        case .system: AppLocalization.string("System")
        case .light: AppLocalization.string("Light")
        case .dark: AppLocalization.string("Dark")
        }
    }

    /// Convert app preference to SwiftUI `ColorScheme`.
    ///
    /// SwiftUI's `.preferredColorScheme(_:)` uses:
    /// - `nil` => no override (follow system)
    /// - `.light` / `.dark` => force specific appearance
    ///
    /// So `system` maps to `nil` naturally.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
