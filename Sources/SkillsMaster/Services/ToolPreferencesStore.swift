import Foundation
import AppKit

@MainActor
@Observable
final class ToolPreferencesStore {

    enum PreferenceError: Error, LocalizedError {
        case unsupportedTerminalApp(URL)

        var errorDescription: String? {
            switch self {
            case .unsupportedTerminalApp(let url):
                return "仅支持将 Terminal、iTerm、Warp 或 Ghostty 设为默认终端：\(url.lastPathComponent)"
            }
        }
    }

    private let defaults: UserDefaults

    var externalEditorAppPath: String?
    var defaultTerminalApp: KnownTerminalApp?
    var defaultTerminalAppPath: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.externalEditorAppPath = defaults.string(forKey: Constants.externalEditorAppPathKey)

        if let rawTerminal = defaults.string(forKey: Constants.defaultTerminalAppKey) {
            self.defaultTerminalApp = KnownTerminalApp(rawValue: rawTerminal)
        } else {
            self.defaultTerminalApp = nil
        }

        self.defaultTerminalAppPath = defaults.string(forKey: Constants.defaultTerminalAppPathKey)
    }

    var externalEditorAppURL: URL? {
        guard let externalEditorAppPath else { return nil }
        let url = URL(fileURLWithPath: externalEditorAppPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var externalEditorDisplayName: String {
        guard let url = externalEditorAppURL else { return "System Default" }
        return applicationDisplayName(for: url) ?? url.deletingPathExtension().lastPathComponent
    }

    var effectiveTerminalApp: KnownTerminalApp {
        defaultTerminalApp ?? .terminal
    }

    var effectiveTerminalAppURL: URL? {
        if let defaultTerminalAppPath {
            let explicitURL = URL(fileURLWithPath: defaultTerminalAppPath)
            if FileManager.default.fileExists(atPath: explicitURL.path) {
                return explicitURL
            }
        }

        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: effectiveTerminalApp.bundleIdentifier)
    }

    var effectiveTerminalDisplayName: String {
        effectiveTerminalApp.displayName
    }

    func setExternalEditorApp(url: URL?) {
        externalEditorAppPath = url?.path
        defaults.set(externalEditorAppPath, forKey: Constants.externalEditorAppPathKey)
    }

    func setDefaultTerminalApp(url: URL?) throws {
        guard let url else {
            defaultTerminalApp = nil
            defaultTerminalAppPath = nil
            defaults.removeObject(forKey: Constants.defaultTerminalAppKey)
            defaults.removeObject(forKey: Constants.defaultTerminalAppPathKey)
            return
        }

        guard let terminalApp = KnownTerminalApp.detect(fromAppBundleURL: url) else {
            throw PreferenceError.unsupportedTerminalApp(url)
        }

        defaultTerminalApp = terminalApp
        defaultTerminalAppPath = url.path
        defaults.set(terminalApp.rawValue, forKey: Constants.defaultTerminalAppKey)
        defaults.set(url.path, forKey: Constants.defaultTerminalAppPathKey)
    }

    func applicationDisplayName(for appURL: URL) -> String? {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard
            let dictionary = NSDictionary(contentsOf: infoPlistURL),
            let displayName = (dictionary["CFBundleDisplayName"] as? String) ?? (dictionary["CFBundleName"] as? String)
        else {
            return nil
        }

        return displayName
    }
}
