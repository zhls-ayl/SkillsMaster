import Foundation
import AppKit

/// `AppUpdateInfo` 表示从 GitHub Release API 获取到的版本信息。
///
/// 这里通过 `Codable` 完成 JSON ↔︎ Swift struct 的映射，并用 `CodingKeys` 处理字段命名差异。
struct AppUpdateInfo: Codable, Sendable {
    /// GitHub Release 的 tag 名，例如 `v1.2.0`。
    let tagName: String
    /// Release 页面 URL。
    let htmlUrl: String
    /// Release 标题。
    let name: String?
    /// Release 描述，通常是 Markdown changelog。
    let body: String?
    /// Release 发布时间（ISO 8601）。
    let publishedAt: String?
    /// Release 附件列表，例如 zip、dmg 等。
    let assets: [Asset]?

    /// Release asset file information
    struct Asset: Codable, Sendable {
        /// Filename (e.g. "SkillsMaster-v1.0.0-universal.zip")
        let name: String
        /// Browser download URL (direct download link, no API authentication required)
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    /// CodingKeys enum maps Swift property names to JSON keys
    /// Swift convention uses camelCase, but GitHub API returns snake_case,
    /// mapping via CodingKeys (similar to Go struct tag `json:"tag_name"`)
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name
        case body
        case publishedAt = "published_at"
        case assets
    }

    /// Version number with "v" prefix removed
    /// Computed property executes calculation on each access, similar to Java's getter
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// Get download URL for zip file
    ///
    /// Priority: look for real download URL of .zip file in assets (most reliable),
    /// fallback to constructing URL by naming convention if assets is empty.
    /// Benefit of getting URL from assets: works regardless of zip filename changes
    /// (e.g. from SkillsMaster.zip to SkillsMaster-v1.0.0-universal.zip).
    var downloadURL: String {
        // When multiple zip assets are published, prefer the universal archive so in-app updates
        // keep matching the current "download zip -> replace .app" flow across both Intel and Apple Silicon.
        if let universalZipAsset = assets?.first(where: { $0.name.hasSuffix("-universal.zip") }) {
            return universalZipAsset.browserDownloadUrl
        }
        // first(where:) finds first asset ending with .zip (similar to Java Stream's findFirst + filter)
        // hasSuffix checks string suffix (similar to Java's endsWith)
        if let zipAsset = assets?.first(where: { $0.name.hasSuffix(".zip") }) {
            return zipAsset.browserDownloadUrl
        }
        // Fallback: construct URL according to Release workflow naming convention
        // Format: /releases/download/v1.0.0/SkillsMaster-v1.0.0-universal.zip
        return "https://github.com/zhls-ayl/SkillsMaster/releases/download/\(tagName)/SkillsMaster-\(tagName)-universal.zip"
    }
}

enum AppUpdateInstallError: LocalizedError, Equatable {
    case notRunningFromAppBundle
    case translocatedApp(path: String)
    case readOnlyVolume(path: String)
    case missingParentDirectory(path: String)
    case authorizationFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .notRunningFromAppBundle:
            return "当前不是从 `.app` bundle 启动，无法执行应用内更新。请先安装打包后的 SkillsMaster.app 再重试。"
        case let .translocatedApp(path):
            return "当前应用仍处于 macOS App Translocation 环境，无法原地替换更新：\(path)。请先将 SkillsMaster.app 移动到 `/Applications` 或 `~/Applications` 后再重试。"
        case let .readOnlyVolume(path):
            return "当前应用位于只读卷，无法原地替换更新：\(path)。请先将 SkillsMaster.app 移动到可写目录后再重试。"
        case let .missingParentDirectory(path):
            return "未找到当前应用所在目录，无法执行更新：\(path)"
        case let .authorizationFailed(message):
            return message
        }
    }
}

struct AppUpdateInstallationContext: Equatable {
    let appBundleURL: URL
    let requiresAdminPrivileges: Bool
    let relaunchUserID: uid_t
    let relaunchUserName: String
}

/// `UpdateChecker` 负责检查并执行 application update。
///
/// 这里同时涉及 network request、文件操作和安装流程，因此使用 `actor` 保证 thread safety。
actor UpdateChecker {

    /// GitHub API endpoint: get latest Release
    /// Fixed to SkillsMaster repository's releases/latest endpoint
    private let apiURL = "https://api.github.com/repos/zhls-ayl/SkillsMaster/releases/latest"

    /// UserDefaults key for storing last check time
    /// UserDefaults is macOS/iOS lightweight key-value storage (similar to Android's SharedPreferences)
    private static let lastCheckKey = "lastAppUpdateCheckTime"

    // MARK: - Get Latest Release

    /// Get latest Release info from GitHub API
    ///
    /// - Returns: Release info
    /// - Throws: Network error or JSON parsing error (caller decides how to handle)
    ///
    /// Changed to throws instead of silently returning nil, allowing caller (SkillManager) to distinguish
    /// between "silently ignore during automatic check" and "show specific error when user manually triggers" scenarios
    func fetchLatestRelease() async throws -> AppUpdateInfo {
        // guard let is Swift's null-checking syntax (similar to Go's if err != nil { return })
        // If URL construction fails (invalid format), throw badURL error
        guard let url = URL(string: apiURL) else {
            throw URLError(.badURL)
        }

        // `URLRequest` 用来封装 HTTP 请求。
        var request = URLRequest(url: url)
        // 设置 10 秒超时，避免网络异常时 UI 等待过久。
        request.timeoutInterval = 10
        // 通过 `Accept` header 指定 GitHub API 返回 JSON。
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        // `URLSession.shared` 是全局共享的网络会话；`data(for:)` 会返回 `(Data, URLResponse)`。
        let (data, response) = try await URLSession.shared.data(for: request)

        // 检查 HTTP status code。
        // 这里需要先把 `URLResponse` 向下转型为 `HTTPURLResponse` 才能读取 `statusCode`。
        // 注意：`URLSession` 不会把非 200 这类 HTTP 错误自动抛出，需要手动处理。
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            // 尝试从返回的 JSON 中提取 GitHub API 的错误消息。
            let message: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let apiMessage = json["message"] as? String {
                message = apiMessage
            } else {
                message = "HTTP \(httpResponse.statusCode)"
            }
            throw NSError(
                domain: "UpdateChecker",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        // 用 `JSONDecoder` 把 JSON 解码成 Swift struct。
        let decoder = JSONDecoder()
        return try decoder.decode(AppUpdateInfo.self, from: data)
    }

    // MARK: - Check Interval Control

    /// 判断是否应该执行自动更新检查（4 小时间隔）。
    ///
    /// 这里使用 `nonisolated`，因为只读 `UserDefaults`，不依赖 actor 内部可变状态。
    nonisolated func shouldAutoCheck() -> Bool {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: UpdateChecker.lastCheckKey)

        // 如果还从未检查过，就直接允许检查。
        guard lastCheck > 0 else { return true }

        // `Date().timeIntervalSince1970` 返回当前 Unix 时间戳（秒）。
        let now = Date().timeIntervalSince1970
        let fourHours: TimeInterval = 4 * 60 * 60  // 4 小时 = 14400 秒

        // 只有距离上次检查超过 4 小时，才允许自动检查。
        return (now - lastCheck) >= fourHours
    }

    /// 把当前检查时间写入 `UserDefaults`。
    nonisolated func recordCheckTime() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UpdateChecker.lastCheckKey)
    }

    // MARK: - Download Update

    /// 把更新 zip 下载到临时目录。
    ///
    /// 这里通过 `URLSessionDownloadDelegate` 把下载进度回调给调用方。
    func downloadUpdate(from url: String, progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        guard let downloadURL = URL(string: url) else {
            throw URLError(.badURL)
        }

        // `DownloadDelegate` 是一个内部辅助类，用来跟踪下载进度。
        let delegate = DownloadDelegate(progressHandler: progressHandler)

        // 创建带 delegate 的 `URLSession`。
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // `download(from:)` 会启动下载，并在完成后返回临时文件路径。
        let (tempURL, _) = try await session.download(from: downloadURL)

        // 下载结果位于系统临时目录，后续可能被自动清理，因此这里会再移动到自己的临时目录。
        let fm = FileManager.default
        // `NSTemporaryDirectory()` 返回系统临时目录路径。
        let destDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillsMasterUpdate")

        // 创建目标目录；`withIntermediateDirectories: true` 的效果类似 `mkdir -p`。
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent("SkillsMaster.zip")
        // 清理上一次下载遗留的旧文件。
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        // `moveItem` 的效果类似 `mv`。
        try fm.moveItem(at: tempURL, to: destURL)

        return destURL
    }

    // MARK: - Install Update

    /// 执行更新安装：解压 zip → 替换 `.app` bundle → 重启 app。
    ///
    /// 由于运行中的 macOS app 不能直接替换自己的二进制文件，因此这里必须借助外部脚本在退出后完成替换。
    /// This is the standard approach for macOS self-updates (Sparkle framework uses similar approach).
    ///
    /// Flow:
    /// 1. Use ditto to extract zip (macOS built-in tool, handles macOS resource forks better than unzip)
    /// 2. Get current app's Bundle.main.bundlePath
    /// 3. Write a shell script: wait for current process to exit → delete old .app → move new .app → launch new app
    /// 4. Launch script using Process (similar to Java's ProcessBuilder)
    /// 5. Call NSApplication.shared.terminate() to exit current app
    ///
    /// - Parameter zipPath: Path to downloaded zip file
    /// - Throws: Extraction failed or script creation failed
    func installUpdate(zipPath: URL) async throws {
        let fm = FileManager.default

        // 1. Create extraction target directory
        let extractDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillsMasterExtract")
        // Clean up old extraction directory if exists
        if fm.fileExists(atPath: extractDir.path) {
            try fm.removeItem(at: extractDir)
        }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // 2. Use ditto to extract zip
        // ditto is macOS-specific file copy tool, better than unzip at handling:
        // - macOS resource forks
        // - File permissions and ACLs
        // - Symbolic links
        // Process similar to Java's ProcessBuilder or Go's exec.Command
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // -xk flags: x=extract, k=from zip format
        unzipProcess.arguments = ["-xk", zipPath.path, extractDir.path]

        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        // Check ditto exit status (0 means success)
        guard unzipProcess.terminationStatus == 0 else {
            throw NSError(
                domain: "UpdateChecker",
                code: Int(unzipProcess.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "解压更新包失败"]
            )
        }

        // 3. Find extracted .app bundle
        // enumerator recursively traverses directory contents (similar to Python's os.walk or Java's Files.walk)
        let contents = try fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
        // first(where:) finds first element matching condition (similar to Java Stream's findFirst)
        // pathExtension gets file extension (e.g. "SkillsMaster.app" → "app")
        guard let newAppBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            // If .app not at top level, search subdirectories
            var foundApp: URL?
            if let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) {
                // enumerator is NSDirectoryEnumerator implementing IteratorProtocol
                // Use while let to extract elements one by one (similar to Java's Iterator.hasNext/next loop)
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "app" {
                        foundApp = fileURL
                        break
                    }
                }
            }
            guard let appURL = foundApp else {
                throw NSError(
                    domain: "UpdateChecker",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "更新包中未找到 .app bundle"]
                )
            }
            // Found nested .app, continue using it
            try await executeUpdate(newAppPath: appURL, extractDir: extractDir)
            return
        }

        try await executeUpdate(newAppPath: newAppBundle, extractDir: extractDir)
    }

    /// Execute actual replacement and restart operation
    ///
    /// Extracted replacement logic into separate method to avoid code duplication in installUpdate
    ///
    /// - Parameters:
    ///   - newAppPath: Path to extracted new .app bundle
    ///   - extractDir: Extraction temp directory (for cleanup)
    private func executeUpdate(newAppPath: URL, extractDir: URL) async throws {
        let installContext = try Self.resolveInstallationContext()

        // Get current process PID (Process IDentifier)
        // ProcessInfo.processInfo is process info singleton (similar to Java's Runtime)
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // 5. Generate shell update script
        // Script logic:
        // - Loop waiting for current PID to exit (kill -0 checks if process exists, check every 0.5s, max 30s)
        // - Delete old .app bundle
        // - Move new .app bundle to original location
        // - Launch new app
        // - Clean up temp files
        //
        // Uses Swift's multi-line string literal (triple quotes """), similar to Python's triple quotes or Java's text block
        let script = Self.makeUpdateScript(
            currentPID: currentPID,
            targetAppPath: installContext.appBundleURL.path,
            newAppPath: newAppPath.path,
            extractDir: extractDir.path,
            downloadDir: Self.updateDownloadDirectory.path,
            relaunchUserID: installContext.relaunchUserID,
            relaunchUserName: installContext.relaunchUserName
        )

        // Write script to temp file
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillsmaster_update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Set script executable permissions (chmod +x)
        // 0o755 is octal file permission (similar to Unix rwxr-xr-x)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillsmaster_update.log")
        Self.prepareLogFile(at: logURL)

        if installContext.requiresAdminPrivileges {
            try Self.launchPrivilegedUpdateScript(at: scriptURL, logURL: logURL)
        } else {
            try Self.launchUpdateScript(at: scriptURL, logURL: logURL)
        }

        // 7. Exit current app
        // Must call NSApplication.terminate on main thread (UI operations must be on main thread)
        // @MainActor closure ensures execution on main thread (similar to DispatchQueue.main.async)
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    static var updateDownloadDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SkillsMasterUpdate")
    }

    static func resolveInstallationContext(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        relaunchUserID: uid_t = getuid(),
        relaunchUserName: String = NSUserName()
    ) throws -> AppUpdateInstallationContext {
        let appBundleURL = bundleURL.standardizedFileURL

        guard appBundleURL.pathExtension == "app" else {
            throw AppUpdateInstallError.notRunningFromAppBundle
        }

        if appBundleURL.path.contains("/AppTranslocation/") {
            throw AppUpdateInstallError.translocatedApp(path: appBundleURL.path)
        }

        let resourceValues = try? appBundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeURLKey])
        if resourceValues?.volumeIsReadOnly == true {
            throw AppUpdateInstallError.readOnlyVolume(path: appBundleURL.path)
        }

        let parentDirectory = appBundleURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parentDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppUpdateInstallError.missingParentDirectory(path: parentDirectory.path)
        }

        return AppUpdateInstallationContext(
            appBundleURL: appBundleURL,
            requiresAdminPrivileges: !fileManager.isWritableFile(atPath: parentDirectory.path),
            relaunchUserID: relaunchUserID,
            relaunchUserName: relaunchUserName
        )
    }

    static func makeUpdateScript(
        currentPID: Int32,
        targetAppPath: String,
        newAppPath: String,
        extractDir: String,
        downloadDir: String,
        relaunchUserID: uid_t,
        relaunchUserName: String
    ) -> String {
        """
        #!/bin/bash
        set -euo pipefail

        CURRENT_PID=\(currentPID)
        TARGET_APP=\(shellLiteral(targetAppPath))
        NEW_APP=\(shellLiteral(newAppPath))
        EXTRACT_DIR=\(shellLiteral(extractDir))
        DOWNLOAD_DIR=\(shellLiteral(downloadDir))
        ORIGINAL_UID=\(relaunchUserID)
        ORIGINAL_USER=\(shellLiteral(relaunchUserName))
        BACKUP_APP="${TARGET_APP}.backup"

        TIMEOUT=120
        while kill -0 "$CURRENT_PID" 2>/dev/null; do
            sleep 0.5
            TIMEOUT=$((TIMEOUT - 1))
            if [ "$TIMEOUT" -le 0 ]; then
                echo "Timed out waiting for SkillsMaster to exit" >&2
                exit 1
            fi
        done

        if [ ! -d "$NEW_APP" ]; then
            echo "Extracted app bundle not found: $NEW_APP" >&2
            exit 1
        fi

        rm -rf "$BACKUP_APP"
        if [ -e "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP"
        fi

        if ! mv "$NEW_APP" "$TARGET_APP"; then
            echo "Failed to move new app bundle into place" >&2
            if [ -e "$BACKUP_APP" ]; then
                mv "$BACKUP_APP" "$TARGET_APP" || true
            fi
            exit 1
        fi

        rm -rf "$BACKUP_APP"

        restart_app() {
            if [ "$(id -u)" = "$ORIGINAL_UID" ]; then
                open "$TARGET_APP"
                return
            fi

            if launchctl asuser "$ORIGINAL_UID" open "$TARGET_APP"; then
                return
            fi

            if [ -n "$ORIGINAL_USER" ]; then
                if /usr/bin/sudo -u "$ORIGINAL_USER" open "$TARGET_APP"; then
                    return
                fi
            fi

            open "$TARGET_APP"
        }

        restart_app

        rm -rf "$EXTRACT_DIR"
        rm -rf "$DOWNLOAD_DIR"
        """
    }

    private static func launchUpdateScript(at scriptURL: URL, logURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        let logHandle = try FileHandle(forWritingTo: logURL)
        logHandle.seekToEndOfFile()
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
    }

    private static func launchPrivilegedUpdateScript(at scriptURL: URL, logURL: URL) throws {
        let scriptPath = appleScriptLiteral(scriptURL.path)
        let logPath = appleScriptLiteral(logURL.path)
        let appleScript = """
        do shell script "nohup /bin/bash " & quoted form of "\(scriptPath)" & " >>" & quoted form of "\(logPath)" & " 2>&1 &" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData.isEmpty ? outputData : errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            throw AppUpdateInstallError.authorizationFailed(
                message: message?.isEmpty == false
                    ? "管理员授权失败，未执行更新：\(message!)"
                    : "管理员授权失败或已取消，未执行更新。"
            )
        }
    }

    private static func prepareLogFile(at url: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        fileManager.createFile(atPath: url.path, contents: Data())
    }

    private static func shellLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: #"'\"'\"'"#)
        return "'\(escaped)'"
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - URLSession Download Delegate

/// DownloadDelegate is responsible for tracking download progress
///
/// URLSessionDownloadDelegate is Apple's download task delegate protocol (similar to Java's callback interface).
/// Inherits from NSObject because Objective-C runtime requires delegate objects to inherit from NSObject.
/// @Sendable marker indicates this class can be safely passed in concurrent contexts (similar to Java's ThreadSafe annotation).
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// Progress callback closure, receives progress value from 0.0~1.0
    let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @Sendable @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    /// Called when download completes (required protocol method)
    /// No additional handling needed here because URLSession.download(from:) async version returns results directly
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Download complete, async/await version handles automatically
    }

    /// Called when download progress updates
    ///
    /// - Parameters:
    ///   - bytesWritten: Bytes written in this operation
    ///   - totalBytesWritten: Total bytes downloaded so far
    ///   - totalBytesExpectedToWrite: Total file size (if server provides Content-Length)
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // totalBytesExpectedToWrite > 0 ensures server returned file size information
        // NSURLSessionTransferSizeUnknown (-1) indicates unknown size
        guard totalBytesExpectedToWrite > 0 else { return }

        // Double() converts Int64 to Double for floating point division
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }
}
