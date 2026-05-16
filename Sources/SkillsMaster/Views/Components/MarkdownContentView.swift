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

    /// 已解析的 AST `Document`；在后台解析完成之前这里为 `nil`。
    /// `@State` 用于保存当前 `View` 的本地可变状态。
    /// 当这个值变化时，SwiftUI 会自动触发重新渲染。
    @State private var document: Document?

    init(markdownText: String) {
        self.markdownText = markdownText
    }

    init(markdownText: String, allowsChineseTranslation: Bool = false) {
        self.markdownText = markdownText
    }

    init(markdownText: String, translationScope: Any?) {
        self.markdownText = markdownText
    }

    init(
        markdownText: String,
        translationScope: Any?,
        manuallyShowsChineseTranslation: Bool
    ) {
        self.markdownText = markdownText
    }

    var body: some View {
        Group {
            if let document {
                // 未开启翻译时继续保留 lazy 渲染，避免长文档一次性创建全部节点。
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(node: child)
                    }
                }
                .textSelection(.enabled)
                .environment(
                    \.markdownShowsChineseTranslation,
                    false
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
            } else {
                // 解析过程中显示轻量 loading placeholder。
                // 这样可以避免页面在解析期间出现"空白阻塞"的观感。
                // `ProgressView()` 会显示 macOS 原生的 loading 指示器。
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(appLocalized("Rendering..."))
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
    mutating func visitParagraph(_ paragraph: Paragraph) -> AnyView {
        let text = buildInlineText(from: paragraph)

        return AnyView(
            text
                .font(.body)
                // `fixedSize` prevents text from being truncated; it allows the text to grow
                // vertically as needed. `horizontal: false` keeps horizontal wrapping behavior.
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    /// Render a CodeBlock (fenced ``` or indented) as monospaced text with a background
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
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
        )
    }

    /// Render a BlockQuote as text with an accent-colored left bar
    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> AnyView {
        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: 3)

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
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> AnyView {
        AnyView(Divider().padding(.vertical, 4))
    }

    /// Render an HTMLBlock as plain text
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> AnyView {
        AnyView(
            SwiftUI.Text(html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.secondary)
        )
    }

    /// Render a Table as a native SwiftUI Grid with styled header row
    mutating func visitTable(_ table: Markdown.Table) -> AnyView {
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
    mutating func defaultVisit(_ markup: any Markup) -> AnyView {
        if markup.childCount > 0 {
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(markup.children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(node: child)
                    }
                }
            )
        }
        let plainText = markup.format()
        return AnyView(
            SwiftUI.Text(plainText)
                .font(.body)
        )
    }

    // MARK: - Inline Text Building

    /// Build a single SwiftUI.Text by concatenating all inline children of a block element
    private func buildInlineText(from node: any Markup) -> SwiftUI.Text {
        node.children.reduce(SwiftUI.Text("")) { accumulated, child in
            accumulated + renderInlineNode(child)
        }
    }

    /// Render a single inline Markdown node as a styled SwiftUI.Text
    private func renderInlineNode(_ node: any Markup) -> SwiftUI.Text {
        switch node {
        case let text as Markdown.Text:
            return SwiftUI.Text(text.string)

        case let strong as Strong:
            let inner = strong.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderInlineNode(child)
            }
            return inner.bold()

        case let emphasis as Emphasis:
            let inner = emphasis.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderInlineNode(child)
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
               let url = URL(string: destination) {
                if let attributed = try? AttributedString(markdown: "[\(linkText)](\(url.absoluteString))") {
                    return SwiftUI.Text(attributed)
                }
            }
            return SwiftUI.Text(linkText)
                .foregroundColor(.accentColor)

        case let strikethrough as Strikethrough:
            let inner = strikethrough.children.reduce(SwiftUI.Text("")) { acc, child in
                acc + renderInlineNode(child)
            }
            return inner.strikethrough()

        case let softBreak as SoftBreak:
            let _ = softBreak
            return SwiftUI.Text(" ")

        case let lineBreak as LineBreak:
            let _ = lineBreak
            return SwiftUI.Text("\n")

        case let image as Markdown.Image:
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
            return SwiftUI.Text(node.format())
        }
    }

}

// MARK: - List Item View

/// MarkdownListItemView renders a single list item with a marker (bullet or number)
struct MarkdownListItemView: View {
    let listItem: ListItem
    let marker: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            SwiftUI.Text(marker)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

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
struct MarkdownTableView: View {
    let table: Markdown.Table
    let columnAlignments: [HorizontalAlignment]

    private let minColumnWidth: CGFloat = 120

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                renderHeaderRow(table.head)
                Divider()

                let bodyRows = Array(table.body.rows)
                ForEach(Array(bodyRows.enumerated()), id: \.offset) { index, row in
                    renderBodyRow(row, rowIndex: index)
                }
            }
            .font(.subheadline)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .cornerRadius(6)
    }

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
        .background(Color(nsColor: .controlBackgroundColor))
    }

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
        .background(rowIndex % 2 == 0 ? Color(nsColor: .textBackgroundColor).opacity(0.3) : Color.clear)
    }

    private func cellText(_ cell: Markdown.Table.Cell) -> SwiftUI.Text {
        cell.children.reduce(SwiftUI.Text("")) { accumulated, child in
            accumulated + renderCellInlineNode(child)
        }
    }

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
