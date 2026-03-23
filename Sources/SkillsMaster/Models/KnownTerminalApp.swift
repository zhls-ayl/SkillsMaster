import Foundation

enum KnownTerminalApp: String, CaseIterable, Identifiable, Codable {
    case terminal
    case iTerm
    case warp
    case ghostty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        case .warp: "Warp"
        case .ghostty: "Ghostty"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    static func detect(fromAppBundleURL appURL: URL) -> KnownTerminalApp? {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let dictionary = NSDictionary(contentsOf: infoPlistURL),
            let bundleIdentifier = dictionary["CFBundleIdentifier"] as? String
        else {
            return nil
        }

        return allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }
}
