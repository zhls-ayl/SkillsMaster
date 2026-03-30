import SwiftUI
import AppKit

/// `AppDelegate` 负责处理 app-level lifecycle。
/// 在 SwiftUI app 中，通过 `@NSApplicationDelegateAdaptor` 把传统 AppKit lifecycle 接入进来。
/// 这里的主要目的，是解决通过 `swift run` 启动时窗口不会自动前置的问题（因为此时并不是完整的 `.app` bundle）。
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // setActivationPolicy(.regular) tells macOS: this is a normal GUI app
        // Without this line, the bare executable launched from command line is treated as a "background process",
        // won't show an icon in the Dock, and won't create windows
        // .regular = Normal GUI app (with Dock icon and menu bar)
        // .accessory = Accessory app (menu bar only, no Dock icon)
        // .prohibited = Pure background process (no UI)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 激活 app 到前台，确保窗口可见。
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 通过 `swift run` 启动时，并没有完整的 `.app` bundle，
        // 因此 macOS 不会自动从 `Info.plist` 读取 `CFBundleIconFile`。
        // 这里需要手动从 `Bundle.module` 加载 `.icns` 资源，并设置到 `NSApplication`。
        // `Bundle.module` 是 SPM 自动生成的资源入口，指向编译后打包进来的 resource bundle。
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
            // NSImage(contentsOf:) loads image from file URL, supports .icns multi-resolution format
            NSApplication.shared.applicationIconImage = NSImage(contentsOf: iconURL)
        }
    }
}

/// `@main` 标记 app entry point，作用类似 Java 的 `main()` 或 Go 的 `func main()`。
///
/// SwiftUI 的 `App` protocol 用来定义整个应用结构：
/// - `body` 返回 app 的 `Scene`
/// - `WindowGroup` 创建主窗口场景（macOS 支持多窗口）
///
/// `@State` 是 SwiftUI 的本地状态包装器：
/// - 被 `@State` 标记的值发生变化时，相关 `View` 会自动重新渲染
/// - 概念上类似 React 的 `useState` 或 Vue 的 `ref()`
@main
struct SkillsMasterApp: App {

    init() {
        AppLocalization.installBundleOverride()
    }

    /// `SkillManager` 是 app 的核心状态管理器。
    /// 使用 `@State` 可以让 SwiftUI 管理它的生命周期。
    @State private var skillManager = SkillManager()
    @State private var toolPreferences = ToolPreferencesStore()

    /// NSApplicationDelegateAdaptor bridges SwiftUI with traditional AppKit lifecycle
    /// Through AppDelegate we can perform AppKit-level operations at app launch
    /// Used here to solve the issue of windows not auto-activating when launched from command line
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // `WindowGroup` 用于创建主窗口。
        WindowGroup {
            AppSceneRoot(skillManager: skillManager, toolPreferences: toolPreferences) {
                ContentView()
            }
        }
        // 设置窗口默认尺寸。
        .defaultSize(width: 1000, height: 700)

        // `Settings` scene 对应 macOS app 的“偏好设置”窗口。
        // 用户可以通过 `Cmd+,` 打开。
        // .environment(skillManager) injects SkillManager,
        // allowing AboutSettingsView to access update state via @Environment
        // Settings scene and WindowGroup are independent View hierarchies, requiring separate environment injection
        Settings {
            AppSceneRoot(skillManager: skillManager, toolPreferences: toolPreferences) {
                SettingsView()
            }
        }
    }
}

/// Applies theme + language preferences inside a normal `View`, not on the `App` scene
/// itself, so changing `@AppStorage` in Settings reliably re-renders the scene content.
private struct AppSceneRoot<Content: View>: View {
    let skillManager: SkillManager
    let toolPreferences: ToolPreferencesStore
    let content: () -> Content

    @AppStorage(Constants.appThemeModeKey)
    private var appThemeModeRawValue = AppThemeMode.system.rawValue

    @AppStorage(Constants.appLanguageModeKey)
    private var appLanguageModeRawValue = AppLanguageMode.system.rawValue

    private var appThemeMode: AppThemeMode {
        AppThemeMode(rawValue: appThemeModeRawValue) ?? .system
    }

    private var appLanguageMode: AppLanguageMode {
        AppLanguageMode(rawValue: appLanguageModeRawValue) ?? .system
    }

    private var languageRefreshID: String {
        "language-\(appLanguageModeRawValue)"
    }

    var body: some View {
        content()
            // 通过 `.environment` 把共享状态注入整个 `View` tree。
            .environment(skillManager)
            .environment(toolPreferences)
            .environment(\.locale, appLanguageMode.resolvedLocale)
            .id(languageRefreshID)
            .preferredColorScheme(appThemeMode.colorScheme)
    }
}
