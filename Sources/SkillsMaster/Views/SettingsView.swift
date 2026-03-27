import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// SettingsView is the app settings page (opened via Cmd+,)
///
/// TabView renders as system standard preferences window style (with tab bar) on macOS
struct SettingsView: View {

    var body: some View {
        TabView {
            通用SettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            // Custom repositories: GitHub/GitLab SSH sources for Skills
            RepositoriesSettingsView()
                .tabItem {
                    Label("Repositories", systemImage: "archivebox")
                }

            翻译SettingsView()
                .tabItem {
                    Label("翻译", systemImage: "translate")
                }

            关于SettingsView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        // Widened and taller to accommodate repository management and editor / terminal settings.
        .frame(width: 620, height: 640)
    }
}

/// 通用 settings
struct 通用SettingsView: View {

    @Environment(SkillManager.self) private var skillManager
    @Environment(ToolPreferencesStore.self) private var toolPreferences

    @State private var installModeError: String?
    @State private var toolPreferenceError: String?

    /// Persisted appearance mode in UserDefaults.
    ///
    /// `@AppStorage` is a SwiftUI property wrapper that binds a value directly to UserDefaults:
    /// - Reading this property fetches stored value automatically.
    /// - Writing this property updates UserDefaults and triggers SwiftUI view refresh.
    ///
    /// This is similar to "state + persistence" combined in one declaration,
    /// unlike Java/Go/Python where UI state and preferences are often wired manually.
    @AppStorage(Constants.appThemeModeKey)
    private var appThemeModeRawValue = AppThemeMode.system.rawValue

    /// Bridge String storage to strongly typed `AppThemeMode` for Picker binding.
    ///
    /// Why a custom Binding is used:
    /// - UserDefaults stores strings, but Picker works best with typed enum values.
    /// - This conversion layer provides type safety and handles invalid stored values safely.
    private var appThemeModeBinding: Binding<AppThemeMode> {
        Binding(
            get: {
                // Fallback to `.system` if stored value is unknown/corrupted,
                // preventing invalid preference data from breaking UI behavior.
                AppThemeMode(rawValue: appThemeModeRawValue) ?? .system
            },
            set: { newMode in
                appThemeModeRawValue = newMode.rawValue
            }
        )
    }

    private var sortedAgentTypes: [AgentType] {
        AgentType.displayNameLengthSortedCases
    }

    var body: some View {
        Form {
            Section("Appearance") {
                // Picker with .menu style renders as a standard macOS dropdown in Form.
                // The selected enum case is persisted via appThemeModeBinding -> @AppStorage.
                Picker("Theme", selection: appThemeModeBinding) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Agent 默认安装方式") {
                Text("切换后会立即迁移该 Agent 当前由 SkillsMaster 管理的 direct install。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedAgentTypes) { agentType in
                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                AgentIconView(agentType: agentType, size: 14)
                                Text(agentType.displayName)
                            }
                            .frame(width: 150, alignment: .leading)

                            Spacer(minLength: 12)

                            Picker(
                                "",
                                selection: Binding(
                                    get: { skillManager.installMode(for: agentType) },
                                    set: { newMode in
                                        installModeError = nil
                                        Task {
                                            do {
                                                try await skillManager.updateDefaultInstallMode(newMode, for: agentType)
                                            } catch {
                                                installModeError = error.localizedDescription
                                            }
                                        }
                                    }
                                )
                            ) {
                                ForEach(AgentInstallMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                    }
                }

                Text("手工放在 Agent 目录中的 agent-local Skill 不会被这个设置改写。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let installModeError {
                    Label(installModeError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Editor & Terminal") {
                LabeledContent("内置编辑器") {
                    Text("支持 .json / .md / .toml / SKILL.md")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("外置编辑器")
                            Text(toolPreferences.externalEditorDisplayName)
                                .foregroundStyle(.secondary)
                            if let appURL = toolPreferences.externalEditorAppURL {
                                Text(appURL.path)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            } else {
                                Text("未配置时回退到系统默认应用")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button("选择应用…") {
                                chooseExternalEditorApp()
                            }
                            .buttonStyle(.bordered)

                            Button("清除") {
                                toolPreferences.setExternalEditorApp(url: nil)
                                toolPreferenceError = nil
                            }
                            .buttonStyle(.bordered)
                            .disabled(toolPreferences.externalEditorAppURL == nil)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("默认终端")
                            Text(toolPreferences.effectiveTerminalDisplayName)
                                .foregroundStyle(.secondary)
                            Text("支持 Terminal / iTerm / Warp / Ghostty")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button("选择终端…") {
                                chooseDefaultTerminalApp()
                            }
                            .buttonStyle(.bordered)

                            Button("恢复默认") {
                                do {
                                    try toolPreferences.setDefaultTerminalApp(url: nil)
                                    toolPreferenceError = nil
                                } catch {
                                    toolPreferenceError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(toolPreferences.defaultTerminalApp == nil)
                        }
                    }
                }

                if let toolPreferenceError {
                    Label(toolPreferenceError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Paths") {
                LabeledContent("Shared Skills") {
                    Text(Constants.sharedSkillsPath)
                        .textSelection(.enabled)  // Allow users to select and copy
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Lock File") {
                    Text(Constants.lockFilePath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseExternalEditorApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        toolPreferences.setExternalEditorApp(url: url)
        toolPreferenceError = nil
    }

    private func chooseDefaultTerminalApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try toolPreferences.setDefaultTerminalApp(url: url)
            toolPreferenceError = nil
        } catch {
            toolPreferenceError = error.localizedDescription
        }
    }
}

struct 翻译SettingsView: View {

    @AppStorage(Constants.autoTranslationEnabledKey)
    private var autoTranslationEnabled = false

    @AppStorage(Constants.autoTranslationInstalledEnabledKey)
    private var installedEnabled = false

    @AppStorage(Constants.autoTranslationSkillsShEnabledKey)
    private var skillsShEnabled = false

    @AppStorage(Constants.autoTranslationClawHubEnabledKey)
    private var clawHubEnabled = false

    @AppStorage(Constants.autoTranslationSkillsHubEnabledKey)
    private var skillsHubEnabled = false

    @AppStorage(Constants.autoTranslationRepositoriesEnabledKey)
    private var repositoriesEnabled = false

    @AppStorage(Constants.autoTranslationAgentsEnabledKey)
    private var agentsEnabled = false

    var body: some View {
        Form {
            Section("自动翻译") {
                Toggle("启用自动翻译", isOn: $autoTranslationEnabled)

                Text("默认关闭。关闭后，所有 Skill 详情页都只显示原始文档，不再自动请求中文译文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("生效范围") {
                Toggle("Installed", isOn: $installedEnabled)
                Toggle("Skills.sh", isOn: $skillsShEnabled)
                Toggle("ClawHub", isOn: $clawHubEnabled)
                Toggle("SkillsHub", isOn: $skillsHubEnabled)
                Toggle("Repositories", isOn: $repositoriesEnabled)
                Toggle("Agents Skills", isOn: $agentsEnabled)

                Text("总开关关闭时，以下范围设置会被保留但不会生效。`Agent Files` 中的任何文件预览都不会启用自动翻译。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// 关于 page (with app update check UI)
///
/// @Environment(SkillManager.self) gets SkillManager instance from View tree.
/// Injected via Settings { ... .environment(skillManager) } in SkillsMasterApp.
struct 关于SettingsView: View {

    /// Get SkillManager from View environment
    /// @Environment is similar to React's useContext or Android's dependency injection
    @Environment(SkillManager.self) private var skillManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SkillsMaster")
                .font(.title)
                .fontWeight(.bold)

            Text("Native macOS Agent Skills Manager")
                .foregroundStyle(.secondary)

            // Read version number from Info.plist, Bundle.main contains Info.plist when running as .app bundle
            // CFBundleShortVersionString is the user-visible version number (e.g., "1.0.0")
            // Falls back to "dev" if running via swift run (no .app bundle)
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Link is SwiftUI built-in hyperlink component, calls system default browser to open URL when clicked
            // Renders as blue clickable text on macOS, similar to HTML's <a> tag
            Link("GitHub", destination: URL(string: "https://github.com/zhls-ayl/SkillsMaster")!)
                .font(.caption)

            // Divider is horizontal separator line (similar to HTML's <hr>), used to visually separate app info and update status area
            Divider()
                .padding(.horizontal)

            // Update status area: shows different UI based on SkillManager state
            updateStatusView
        }
        .padding()
        // .task automatically triggers update check when View first appears (subject to 4-hour interval limit)
        // This way when user opens settings page, if more than 4 hours since last check, it will automatically check
        .task {
            await skillManager.checkForAppUpdate()
        }
    }

    /// Update status view: dynamically displays different UI based on SkillManager's update-related state properties
    ///
    /// @ViewBuilder allows using if-else in computed properties to return different View types
    /// (Swift's View is strongly typed, different branches returning different types need @ViewBuilder to wrap uniformly)
    @ViewBuilder
    private var updateStatusView: some View {
        if skillManager.isCheckingAppUpdate {
            // Checking state: show spinning indicator
            HStack(spacing: 8) {
                // ProgressView() without arguments shows indeterminate spinning indicator (spinner)
                // controlSize(.small) controls size to small
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if skillManager.isDownloadingUpdate {
            // Downloading state: show determinate progress bar
            VStack(spacing: 6) {
                // ProgressView(value:total:) shows determinate horizontal progress bar
                // value is current value, total is maximum value (default 1.0)
                ProgressView(value: skillManager.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                // Show percentage (multiply by 100 and keep integer)
                // Int() truncates Double to integer (similar to Java's (int) cast)
                Text("Downloading... \(Int(skillManager.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()  // Monospaced digit font, avoids text jitter when percentage changes
            }
        } else if let error = skillManager.updateError {
            // Error state: show red error message and retry button
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)  // Limit error message to max 2 lines
                }

                Button("Retry") {
                    Task { await skillManager.checkForAppUpdate(force: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if let updateInfo = skillManager.appUpdateInfo {
            // Has available update state: show new version number, update button and GitHub link
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    // Use orange arrow icon to indicate update is available
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Update available: v\(updateInfo.version)")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                HStack(spacing: 12) {
                    // "立即更新" button triggers download and install update
                    // .borderedProminent is filled prominent button style (similar to Material Design's Filled Button)
                    Button("立即更新") {
                        Task { await skillManager.performUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // "在 GitHub 查看" link opens Release page in browser
                    // Uses Link component instead of Button because it's external navigation (opens browser)
                    if let url = URL(string: updateInfo.htmlUrl) {
                        Link("在 GitHub 查看", destination: url)
                            .font(.caption)
                    }
                }
            }
        } else {
            // No update/not checked state: show manual check button
            // force: true ignores 4-hour interval limit, executes check immediately
            Button("检查更新") {
                Task { await skillManager.checkForAppUpdate(force: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
