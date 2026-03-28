import SwiftUI
// 引入 Apple 官方 `swift-markdown` 库，用于解析 Markdown AST。
// 这个库提供了 `Document`、`MarkupVisitor` 以及 `Heading`、`Paragraph` 等强类型 AST node。
// 由于 module 名就叫 `Markdown`，因此作用域里会同时出现 `Markdown.Text`（AST node）
// 和 `SwiftUI.Text`（View）；需要时要显式写 module 前缀来消除歧义。
import Markdown

/// `MarkdownContentView` 负责把 Markdown 字符串渲染成原生 SwiftUI 视图。
///
/// 实现方式是：先用 `swift-markdown` 把原始文本解析成 AST（Abstract Syntax Tree），
/// 再通过自定义 `MarkupVisitor` 遍历 AST，把每个 node 转成 SwiftUI `View`。
///
/// 这种方案不依赖 `WebView`，优点包括：
/// - 原生 macOS 外观，更容易和系统字体、颜色、dark mode 保持一致
/// - 渲染开销更低，不需要嵌入 web engine
/// - 可以直接启用 `textSelection(.enabled)`
///
/// `Document(parsing:)` 属于 CPU-bound 操作，如果直接在 `body` 里执行会阻塞 main thread。
/// 因此这里使用 `@State` + `.task(id:)` 在后台完成解析，并在解析过程中展示轻量占位 UI。
struct MarkdownContentView: View {

    /// 需要被解析和渲染的原始 Markdown 字符串。
    let markdownText: String

    /// 当前 markdown 内容所属的翻译作用域。
    /// 详情页会显式传入 scope；普通文件预览保持 `nil`，避免把“文档翻译”扩散到所有 Markdown 文件。
    let translationScope: SkillTranslationScope?

    /// 仅当前应用会话有效的手动翻译状态；由上层详情页按当前 Skill 独立维护，不写回全局设置。
    let manuallyShowsChineseTranslation: Bool

    /// 已解析的 AST `Document`；在后台解析完成之前这里为 `nil`。
    /// `@State` 用于保存当前 `View` 的本地可变状态。
    /// 当这个值变化时，SwiftUI 会自动触发重新渲染。
    @State private var document: Document?

    @Environment(SkillManager.self) private var skillManager

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

    init(markdownText: String, allowsChineseTranslation: Bool = false) {
        self.markdownText = markdownText
        self.translationScope = allowsChineseTranslation ? .installed : nil
        self.manuallyShowsChineseTranslation = false
    }

    init(markdownText: String, translationScope: SkillTranslationScope?) {
        self.markdownText = markdownText
        self.translationScope = translationScope
        self.manuallyShowsChineseTranslation = false
    }

    init(
        markdownText: String,
        translationScope: SkillTranslationScope?,
        manuallyShowsChineseTranslation: Bool
    ) {
        self.markdownText = markdownText
        self.translationScope = translationScope
        self.manuallyShowsChineseTranslation = manuallyShowsChineseTranslation
    }

    var body: some View {
        let translationEnabledOnThisScreen = TranslationSettingsPolicy.isEnabled(
            autoTranslationEnabled: autoTranslationEnabled,
            manualTranslationEnabled: manuallyShowsChineseTranslation,
            scope: translationScope,
            enabledScopes: enabledScopes
        )
        let showsChineseTranslation = translationEnabledOnThisScreen && skillManager.shouldShowChineseTranslation

        Group {
            if let document {
                // 解析完成后，按完整 AST 渲染 SwiftUI 视图。
                // 开启逐段翻译后，每个段落都会在异步完成时改变自身高度。
                // `ScrollView + LazyVStack` 在这种“滚动中动态高度变化”的场景下很容易反复回收与重建子视图，
                // 进而触发重复翻译与布局抖动。这里在翻译开启时退回稳定的 `VStack`。
                Group {
                    if showsChineseTranslation {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                                MarkdownNodeView(node: child)
                            }
                        }
                    } else {
                        // 未开启翻译时继续保留 lazy 渲染，避免长文档一次性创建全部节点。
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                                MarkdownNodeView(node: child)
                            }
                        }
                    }
                }
                .textSelection(.enabled)
                .environment(
                    \.markdownShowsChineseTranslation,
                    showsChineseTranslation
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
            } else {
                // 解析过程中显示轻量 loading placeholder。
                // 这样可以避免页面在解析期间出现“空白阻塞”的观感。
                // `ProgressView()` 会显示 macOS 原生的 loading 指示器。
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Rendering...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        // `.task(id: markdownText)` 会在 `markdownText` 变化时启动新的 async Task。
        // 在 Swift concurrency 中，`Task { }` 可以把这类工作交给 cooperative thread pool 执行，
        // 从而避免 `Document(parsing:)` 阻塞 UI。
        // 当 `markdownText` 变化时，旧任务会自动取消，并启动一轮新的解析。
        .task(id: markdownText) {
            // 先重置为 `nil`，让 loading placeholder 能立刻显示，
            // 避免内容切换时出现旧内容闪烁。
            document = nil
            // `Document(parsing:)` 属于 CPU-bound 工作，把它放进 `Task` 可以避免阻塞 UI。
            // 这样 Swift 就可以把解析任务调度到后台执行，让 main actor 保持空闲。
            // 等结果准备好之后，再回到主线程把值写入 `@State`。
            let parsed = Document(parsing: markdownText)
            // 给 `@State` 赋值必须回到 main actor（这是 SwiftUI 的要求）。
            // 这里的赋值是安全的，并会触发重新渲染来展示解析结果。
            document = parsed
        }
        .task(id: translationEnabledOnThisScreen) {
            await skillManager.prepareSkillContentTranslationIfNeeded(
                translationEnabledOnThisScreen: translationEnabledOnThisScreen
            )
        }
    }

    private var enabledScopes: Set<SkillTranslationScope> {
        var scopes = Set<SkillTranslationScope>()
        if installedEnabled { scopes.insert(.installed) }
        if skillsShEnabled { scopes.insert(.skillsSh) }
        if clawHubEnabled { scopes.insert(.clawHub) }
        if skillsHubEnabled { scopes.insert(.skillsHub) }
        if repositoriesEnabled { scopes.insert(.repositories) }
        if agentsEnabled { scopes.insert(.agents) }
        return scopes
    }
}

private struct TranslatedParagraphView: View {
    let englishText: SwiftUI.Text
    let plainEnglishText: String

    @Environment(SkillManager.self) private var skillManager

    @State private var translatedText: String?
    @State private var translationFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            englishText
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let translatedText {
                Text(translatedText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if translationFailed {
                Text("翻译失败")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text("翻译中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .task(id: plainEnglishText) {
            let input = plainEnglishText
            guard !input.isEmpty else {
                translatedText = nil
                translationFailed = false
                return
            }

            do {
                translationFailed = false
                translatedText = try await skillManager.translateEnglishParagraphToChinese(input)
            } catch {
                translatedText = nil
                translationFailed = true
            }
        }
    }
}

// MARK: - Block Node View

/// `MarkdownNodeView` 负责把单个 Markdown AST node 渲染成 SwiftUI `View`。
///
/// 这个辅助结构的作用，是把 `MarkupVisitor`（内部依赖 `mutating` 方法）和 SwiftUI 的 `View` system 衔接起来。
/// 由于 SwiftUI `View` 是 `struct`，而 `body` 又是非 `mutating` 的 computed property，
/// 所以不能直接在 `body` 里调用 `mutating visitor` 方法。
///
/// `MarkupVisitor` 本身采用的是典型的 Visitor pattern：
/// 不同 AST node 会分发到各自的 `visit*` 方法中。
struct MarkdownNodeView: View {

    /// 当前要渲染的 Markdown AST node。
    let node: any Markup

    @Environment(\.markdownShowsChineseTranslation) private var markdownShowsChineseTranslation

    var body: some View {
        // 创建 visitor，并把 node 分发到对应的 `visit*` 方法。
        // `visit()` 是入口方法，会根据 node 的实际类型分发到 `visitHeading()`、`visitParagraph()` 等具体实现。
        var visitor = SwiftUIMarkdownVisitor(showsChineseTranslation: markdownShowsChineseTranslation)
        let result = visitor.visit(node)
        result
    }
}

private struct MarkdownShowsChineseTranslationKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private extension EnvironmentValues {
    var markdownShowsChineseTranslation: Bool {
        get { self[MarkdownShowsChineseTranslationKey.self] }
        set { self[MarkdownShowsChineseTranslationKey.self] = newValue }
    }
}

// MARK: - Markdown Visitor

/// SwiftUIMarkdownVisitor converts Markdown AST nodes into SwiftUI views
///
/// Implements the `MarkupVisitor` protocol from swift-markdown.
/// The `Result` associated type is set to `AnyView` — each `visit*` method returns
/// a type-erased SwiftUI view. Type erasure (`AnyView`) is needed because different
/// visit methods return different concrete view types, and Swift requires a single return type.
///
/// Supported block elements:
/// - Heading (H1-H6) → sized Text with appropriate font weight
/// - Paragraph → inline-formatted Text (handles bold, italic, code, links)
/// - CodeBlock → monospaced text with background, optional language label
/// - BlockQuote → accent-colored bar with secondary text
/// - UnorderedList / OrderedList → bullet/number markers with indentation
/// - Table → native Grid with header row styling and column alignment
/// - ThematicBreak (---) → Divider
///
/// Supported inline elements (within paragraphs):
/// - Strong (bold), Emphasis (italic), InlineCode (monospaced), Link (clickable),
///   Strikethrough, and plain Text
struct SwiftUIMarkdownVisitor: MarkupVisitor {

    // `typealias` 把 `MarkupVisitor` 的 `Result` 统一声明为 `AnyView`。
    // 这样每个 `visit*` 方法都返回同一种结果类型。
    // `AnyView` 是 SwiftUI 中常见的 type-erased `View` 包装器。
    typealias Result = AnyView

    let showsChineseTranslation: Bool

    init(showsChineseTranslation: Bool = false) {
        self.showsChineseTranslation = showsChineseTranslation
    }

    // MARK: - Block Elements

    /// Render a Heading node (# H1, ## H2, etc.) as a bold Text with sized font
    ///
    /// `heading.level` is 1-6 corresponding to # through ######.
    /// We map each level to a SwiftUI Font: .title for H1, .title2 for H2, etc.
    mutating func visitHeading(_ heading: Heading) -> AnyView {
        let text = buildInlineText(from: heading)
        let font: Font = switch heading.level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        case 4: .headline
        case 5: .subheadline
        default: .body
        }

        return AnyView(
            text
                .font(font)
                .fontWeight(.bold)
                // Add top padding for visual separation between sections
                .padding(.top, heading.level <= 2 ? 8 : 4)
        )
    }

    /// Render a Paragraph node as formatted inline text
    ///
    /// A Paragraph contains inline children (Text, Strong, Emphasis, InlineCode, Link, etc.).
    /// We build a single `SwiftUI.Text` by concatenating inline elements with `+` operator.
    mutating func visitParagraph(_ paragraph: Paragraph) -> AnyView {
        let text = buildInlineText(from: paragraph)
        let plain = MarkdownPlainTextExtractor.extract(from: paragraph)

        if showsChineseTranslation, !plain.isEmpty {
            return AnyView(
                TranslatedParagraphView(
                    englishText: text,
                    plainEnglishText: plain
                )
            )
        }

        return AnyView(
            text
                .font(.body)
                // `fixedSize` prevents text from being truncated; it allows the text to grow
                // vertically as needed. `horizontal: false` keeps horizontal wrapping behavior.
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    /// Render a CodeBlock (fenced ``` or indented) as monospaced text with a background
    ///
    /// `codeBlock.code` contains the raw code string.
    /// `codeBlock.language` is the optional language identifier after ``` (e.g., "swift", "python").
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> AnyView {
        let code = codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines)

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                // Optional language label (e.g., "swift", "bash")
                if let language = codeBlock.language, !language.isEmpty {
                    SwiftUI.Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }

                // Code content in monospaced font
                SwiftUI.Text(code)
                    // `.system(.body, design: .monospaced)` creates a system font with monospace design,
                    // similar to using "Courier New" in CSS but using the system monospace font
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Use system text background color — adapts to dark/light mode automatically
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    // `overlay` draws a border on top of the view; RoundedRectangle defines the border shape
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
        )
    }

    /// Render a BlockQuote as text with an accent-colored left bar
    ///
    /// BlockQuote is a container that can hold paragraphs, lists, etc.
    /// We render child blocks recursively with indentation and a colored accent bar.
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> AnyView {
        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                // Accent-colored left bar — mimics the traditional blockquote style (like in Slack/Discord)
                // `RoundedRectangle` with small corner radius creates a pill-shaped bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)

                // Render child blocks recursively (blockquotes can contain paragraphs, lists, etc.)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(node: child)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
        )
    }

    /// Render an UnorderedList (- item, * item) with bullet markers
    ///
    /// Each child of an UnorderedList is a ListItem node.
    /// We render each with a bullet point ("•") prefix.
    /// Uses `MarkdownListItemView` helper to avoid capturing `mutating self` in escaping closures —
    /// Swift doesn't allow mutating struct methods to be captured in @ViewBuilder closures.
    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> AnyView {
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(unorderedList.children.enumerated()), id: \.offset) { _, child in
                    if let listItem = child as? ListItem {
                        MarkdownListItemView(listItem: listItem, marker: "•")
                    }
                }
            }
        )
    }

    /// Render an OrderedList (1. item, 2. item) with number markers
    ///
    /// Similar to UnorderedList but with sequential numbers instead of bullets.
    /// `enumerated()` provides the index for numbering (0-based, so we add 1).
    mutating func visitOrderedList(_ orderedList: OrderedList) -> AnyView {
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(orderedList.children.enumerated()), id: \.offset) { index, child in
                    if let listItem = child as? ListItem {
                        MarkdownListItemView(listItem: listItem, marker: "\(index + 1).")
                    }
                }
            }
        )
    }

    /// Render a ThematicBreak (---) as a horizontal divider
    ///
    /// `Divider()` is SwiftUI's horizontal rule — a thin line that spans the full width.
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> AnyView {
        AnyView(Divider().padding(.vertical, 4))
    }

    /// Render an HTMLBlock as plain text
    ///
    /// Some SKILL.md files may contain raw HTML blocks.
    /// We display them as plain text rather than trying to interpret HTML,
    /// since SwiftUI has no built-in HTML renderer.
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> AnyView {
        AnyView(
            SwiftUI.Text(html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.secondary)
        )
    }

    /// Render a Table as a native SwiftUI Grid with styled header row
    ///
    /// Markdown tables have this AST structure:
    /// ```
    /// Table
    ///   ├── Table.Head (single header row)
    ///   │     └── Table.Cell × N (header cells)
    ///   └── Table.Body
    ///         └── Table.Row × M (body rows)
    ///               └── Table.Cell × N (body cells)
    /// ```
    ///
    /// We use `MarkdownTableView` (a separate View struct) to render the table,
    /// because SwiftUI's `Grid` requires `@ViewBuilder` closures which can't capture
    /// `mutating self` from the visitor.
    ///
    /// Column alignment from the markdown source (`:---`, `:---:`, `---:`) is passed through
    /// to align text within each cell. The header row gets bold text and a colored background.
    mutating func visitTable(_ table: Markdown.Table) -> AnyView {
        // Extract column alignments from the Table AST node.
        // `table.columnAlignments` is `[Table.ColumnAlignment?]` — nil means default (leading).
        // We convert to SwiftUI `HorizontalAlignment` for use in Grid cells.
        let alignments = table.columnAlignments.map { alignment -> HorizontalAlignment in
            switch alignment {
            case .center: .center
            case .right: .trailing
            case .left, .none: .leading
            }
        }

        return AnyView(
            MarkdownTableView(table: table, columnAlignments: alignments)
        )
    }

    // MARK: - Default Handler

    /// Default handler for any unrecognized node types
    ///
    /// The `defaultVisit` method is called for node types that don't have a specific `visit*` override.
    /// We render their children recursively to handle nested structures gracefully.
    /// This ensures the visitor doesn't crash on unknown node types — it just renders what it can.
    mutating func defaultVisit(_ markup: any Markup) -> AnyView {
        // If the node has children, render them recursively
        if markup.childCount > 0 {
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(markup.children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(node: child)
                    }
                }
            )
        }
        // Leaf node with no specific handler — render its plain text content
        let plainText = markup.format()
        return AnyView(
            SwiftUI.Text(plainText)
                .font(.body)
        )
    }

    // MARK: - Inline Text Building

    /// Build a single SwiftUI.Text by concatenating all inline children of a block element
    ///
    /// Block elements like Heading and Paragraph contain inline children (Text, Strong, Emphasis, etc.).
    /// SwiftUI's `Text` supports concatenation with `+`, so we can build a single rich text
    /// by combining styled text fragments.
    ///
    /// Example: "Hello **world** and `code`" becomes:
    /// `Text("Hello ") + Text("world").bold() + Text(" and ") + Text("code").font(.monospaced)`
    ///
    /// - Parameter node: A block-level Markup node whose children are inline elements
    /// - Returns: A concatenated SwiftUI.Text with all inline formatting applied
    private func buildInlineText(from node: any Markup) -> SwiftUI.Text {
        // Reduce all inline children into a single concatenated Text.
        // `reduce` is similar to Java Stream's reduce() or Python's functools.reduce().
        // Start with an empty Text, then append each child's rendered text with `+`.
        node.children.reduce(SwiftUI.Text("")) { accumulated, child in
            accumulated + renderInlineNode(child)
        }
    }

    /// Render a single inline Markdown node as a styled SwiftUI.Text
    ///
    /// Handles: plain text, bold, italic, inline code, links, strikethrough.
    /// Recursively processes nested inline elements (e.g., bold text inside a link).
    ///
    /// - Parameter node: An inline Markup node
    /// - Returns: A styled SwiftUI.Text fragment
    private func renderInlineNode(_ node: any Markup) -> SwiftUI.Text {
        // `switch` with `as` pattern matching — tests the runtime type of the node
        // and binds it to a typed variable in each case.
        // This is Swift's type-safe alternative to Java's instanceof chain.
        switch node {
        case let text as Markdown.Text:
            // Plain text node — render as-is
            // Note: `Markdown.Text` is the AST node type, fully qualified to avoid
            // confusion with `SwiftUI.Text` (the view type)
            return SwiftUI.Text(text.string)

        case let strong as Strong:
            // Bold text (**bold** or __bold__)
            // Recursively render children in case of nested formatting (e.g., **bold *and italic***)
            let inner = strong.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderInlineNode(child)
            }
            return inner.bold()

        case let emphasis as Emphasis:
            // Italic text (*italic* or _italic_)
            let inner = emphasis.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderInlineNode(child)
            }
            return inner.italic()

        case let code as InlineCode:
            // Inline code (`code`) — monospaced font with subtle background
            // `.font(.system(.body, design: .monospaced))` applies monospace design
            return SwiftUI.Text(code.code)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.orange)

        case let link as Markdown.Link:
            // Clickable link [text](url) — renders as blue underlined text
            // SwiftUI.Text supports markdown-style links via `AttributedString`
            let linkText = link.children.reduce("") { acc, child in
                if let text = child as? Markdown.Text {
                    return acc + text.string
                }
                return acc + child.format()
            }
            if let destination = link.destination,
               let url = URL(string: destination) {
                // Create a clickable link using markdown syntax in AttributedString.
                // `try?` silently handles parsing failures — falls back to plain text.
                if let attributed = try? AttributedString(markdown: "[\(linkText)](\(url.absoluteString))") {
                    return SwiftUI.Text(attributed)
                }
            }
            // Fallback: render link text without clickability
            return SwiftUI.Text(linkText)
                .foregroundColor(.accentColor)

        case let strikethrough as Strikethrough:
            // Strikethrough text (~~text~~)
            let inner = strikethrough.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderInlineNode(child)
            }
            return inner.strikethrough()

        case let softBreak as SoftBreak:
            // Soft line break (single newline in markdown source) — rendered as a space
            let _ = softBreak // suppress unused variable warning
            return SwiftUI.Text(" ")

        case let lineBreak as LineBreak:
            // Hard line break (two spaces + newline or backslash + newline) — rendered as newline
            let _ = lineBreak
            return SwiftUI.Text("\n")

        case let image as Markdown.Image:
            // Image ![alt](url) — we can't render images inline in Text,
            // so show the alt text or URL as a placeholder
            let altText = image.children.reduce("") { acc, child in
                if let text = child as? Markdown.Text {
                    return acc + text.string
                }
                return acc + child.format()
            }
            let display = altText.isEmpty ? (image.source ?? "image") : altText
            return SwiftUI.Text("[\(display)]")
                .foregroundColor(.secondary)

        default:
            // Unknown inline node — render its raw text format
            // `format()` converts the AST node back to its markdown source text
            return SwiftUI.Text(node.format())
        }
    }

}

// MARK: - List Item View

/// MarkdownListItemView renders a single list item with a marker (bullet or number)
///
/// Extracted as a standalone view struct because `renderListItem` was a `mutating` method
/// on `SwiftUIMarkdownVisitor` — Swift doesn't allow capturing `mutating self` in
/// `@escaping` closures like SwiftUI's `ForEach` content builder.
/// By using a separate View struct, we avoid the escaping closure restriction entirely.
///
/// ListItems can contain paragraphs, nested lists, code blocks, etc.
/// We render the marker (e.g., "•" or "1.") alongside all child content.
struct MarkdownListItemView: View {
    /// The ListItem AST node from swift-markdown
    let listItem: ListItem
    /// The marker string ("•" for unordered, "1." / "2." etc. for ordered)
    let marker: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Marker text (bullet or number) — fixed width for alignment across list items
            SwiftUI.Text(marker)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            // Content: render all children of the list item using MarkdownNodeView
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(listItem.children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child)
                }
            }
        }
    }
}

// MARK: - Table View

/// MarkdownTableView renders a Markdown table as a native SwiftUI Grid
///
/// Extracted as a standalone view struct (like `MarkdownListItemView`) because the visitor's
/// `mutating` methods can't be captured in SwiftUI's `@ViewBuilder` closures.
///
/// Layout approach:
/// - Uses SwiftUI `Grid` (macOS 14+) which aligns columns automatically — similar to HTML `<table>`
/// - Header row: bold text with a tinted background and bottom separator
/// - Body rows: alternating background for readability (even rows get a subtle tint)
/// - Column alignment: respects markdown alignment syntax (`:---` left, `:---:` center, `---:` right)
/// - Cells can contain inline formatting (bold, code, links) rendered via inline text builder
///
/// The table is wrapped in a horizontal ScrollView so wide tables don't force the layout to overflow.
struct MarkdownTableView: View {
    /// The Table AST node from swift-markdown
    let table: Markdown.Table
    /// Converted column alignments (from `Table.ColumnAlignment?` to `HorizontalAlignment`)
    let columnAlignments: [HorizontalAlignment]

    private let minColumnWidth: CGFloat = 120

    var body: some View {
        // ScrollView(.horizontal) allows wide tables to scroll horizontally
        // instead of compressing columns or breaking the layout.
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Render header row
                renderHeaderRow(table.head)

                // Thin separator line between header and body
                // `Divider()` inside a Grid spans the full width
                Divider()

                // Render body rows
                let bodyRows = Array(table.body.rows)
                ForEach(Array(bodyRows.enumerated()), id: \.offset) { index, row in
                    renderBodyRow(row, rowIndex: index)
                }
            }
            .font(.subheadline)
        }
        // Add a subtle border around the entire table
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .cornerRadius(6)
    }

    /// Render the table header row with bold text and tinted background
    ///
    /// `Table.Head` conforms to `TableCellContainer` — its children are `Table.Cell` nodes.
    /// We iterate through cells and apply column alignment from `columnAlignments`.
    private func renderHeaderRow(_ head: Markdown.Table.Head) -> some View {
        GridRow {
            ForEach(Array(head.children.enumerated()), id: \.offset) { colIndex, child in
                if let cell = child as? Markdown.Table.Cell {
                    cellText(cell)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(textAlignment(for: colIndex))
                        .frame(minWidth: minColumnWidth, alignment: alignment(for: colIndex))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
        }
        // Header background: subtle tint for visual distinction from body rows
        // `Color(nsColor: .controlBackgroundColor)` adapts to dark/light mode
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Render a table body row with alternating background
    ///
    /// `Table.Row`'s children are `Table.Cell` nodes, same as the header.
    /// Even-indexed rows get a subtle background tint for zebra-stripe readability.
    ///
    /// - Parameters:
    ///   - row: The Table.Row AST node
    ///   - rowIndex: Zero-based row index (used for alternating background)
    private func renderBodyRow(_ row: Markdown.Table.Row, rowIndex: Int) -> some View {
        GridRow {
            ForEach(Array(row.children.enumerated()), id: \.offset) { colIndex, child in
                if let cell = child as? Markdown.Table.Cell {
                    cellText(cell)
                        .multilineTextAlignment(textAlignment(for: colIndex))
                        .frame(minWidth: minColumnWidth, alignment: alignment(for: colIndex))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
        // Zebra-stripe: even rows get a subtle background for visual separation.
        // Odd rows are transparent (default background).
        .background(rowIndex % 2 == 0 ? Color(nsColor: .textBackgroundColor).opacity(0.3) : Color.clear)
    }

    /// Build inline-formatted SwiftUI.Text for a table cell
    ///
    /// Table cells can contain inline markup (bold, code, links, etc.).
    /// We concatenate all inline children into a single styled `Text`,
    /// using the same inline rendering logic as paragraphs.
    ///
    /// - Parameter cell: The Table.Cell AST node
    /// - Returns: A concatenated SwiftUI.Text with inline formatting
    private func cellText(_ cell: Markdown.Table.Cell) -> SwiftUI.Text {
        cell.children.reduce(SwiftUI.Text("")) { accumulated, child in
            accumulated + renderCellInlineNode(child)
        }
    }

    /// Get the alignment for a column index
    ///
    /// Falls back to `.leading` if the column index is out of bounds
    /// (e.g., if some rows have more cells than the alignment array).
    private func alignment(for columnIndex: Int) -> Alignment {
        guard columnIndex < columnAlignments.count else { return .leading }
        return Alignment(horizontal: columnAlignments[columnIndex], vertical: .center)
    }

    private func textAlignment(for columnIndex: Int) -> TextAlignment {
        guard columnIndex < columnAlignments.count else { return .leading }
        switch columnAlignments[columnIndex] {
        case .center:
            return .center
        case .trailing:
            return .trailing
        default:
            return .leading
        }
    }

    /// Render a single inline node within a table cell as styled SwiftUI.Text
    ///
    /// This mirrors `SwiftUIMarkdownVisitor.renderInlineNode` but adapted for use
    /// in a non-mutating View context. Table cells support the same inline formatting
    /// as paragraphs: bold, italic, inline code, links, strikethrough.
    private func renderCellInlineNode(_ node: any Markup) -> SwiftUI.Text {
        switch node {
        case let text as Markdown.Text:
            return SwiftUI.Text(text.string)

        case let strong as Strong:
            let inner = strong.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderCellInlineNode(child)
            }
            return inner.bold()

        case let emphasis as Emphasis:
            let inner = emphasis.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderCellInlineNode(child)
            }
            return inner.italic()

        case let code as InlineCode:
            return SwiftUI.Text(code.code)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.orange)

        case let link as Markdown.Link:
            let linkText = link.children.reduce("") { acc, child in
                if let text = child as? Markdown.Text {
                    return acc + text.string
                }
                return acc + child.format()
            }
            if let destination = link.destination,
               let url = URL(string: destination),
               let attributed = try? AttributedString(markdown: "[\(linkText)](\(url.absoluteString))") {
                return SwiftUI.Text(attributed)
            }
            return SwiftUI.Text(linkText).foregroundColor(.accentColor)

        case let strikethrough as Strikethrough:
            let inner = strikethrough.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderCellInlineNode(child)
            }
            return inner.strikethrough()

        case is SoftBreak:
            return SwiftUI.Text(" ")

        case is LineBreak:
            return SwiftUI.Text("\n")

        default:
            return SwiftUI.Text(node.format())
        }
    }
}
