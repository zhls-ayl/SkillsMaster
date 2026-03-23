import Foundation
import AppKit

enum ApplicationLauncher {

    enum LaunchError: Error, LocalizedError {
        case appNotConfigured(String)
        case appNotFound(String)
        case openFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotConfigured(let description):
                return description
            case .appNotFound(let description):
                return description
            case .openFailed(let description):
                return description
            }
        }
    }

    @MainActor
    static func revealInFinder(itemURL: URL, fileManager: FileManager = .default) {
        NSWorkspace.shared.activateFileViewerSelecting([
            finderRevealURL(for: itemURL, fileManager: fileManager)
        ])
    }

    static func finderRevealURL(for itemURL: URL, fileManager: FileManager = .default) -> URL {
        var candidateURL = itemURL.standardizedFileURL

        while !fileManager.fileExists(atPath: candidateURL.path) {
            let parentURL = candidateURL.deletingLastPathComponent().standardizedFileURL
            guard parentURL.path != candidateURL.path else { break }
            candidateURL = parentURL
        }

        return candidateURL
    }

    @MainActor
    static func openInExternalEditor(
        itemURL: URL,
        preferences: ToolPreferencesStore
    ) throws {
        guard let appURL = preferences.externalEditorAppURL else {
            if NSWorkspace.shared.open(itemURL) {
                return
            }
            throw LaunchError.appNotConfigured("未配置外置编辑器，且无法使用系统默认应用打开该项。")
        }

        try open(itemURL: itemURL, appURL: appURL)
    }

    @MainActor
    static func openInTerminal(
        directoryURL: URL,
        preferences: ToolPreferencesStore
    ) throws {
        if let appURL = preferences.effectiveTerminalAppURL {
            try open(itemURL: directoryURL, appURL: appURL)
            return
        }

        throw LaunchError.appNotFound("找不到默认终端 \(preferences.effectiveTerminalDisplayName) 的安装位置。")
    }

    private static func open(itemURL: URL, appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appURL.path, itemURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LaunchError.openFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
            let message = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.openFailed(message?.isEmpty == false ? message! : "无法使用 \(appURL.lastPathComponent) 打开该项。")
        }
    }
}
