import SwiftUI

/// 统一渲染来自 `SKILL.md` frontmatter 的 description 文本。
///
/// description 属于纯文本 metadata，不应被当作 Markdown 解释。
/// 同时通过固定纵向尺寸，确保字符串中真实存在的换行可以按多行显示。
struct SkillDescriptionText: View {
    let text: String
    var font: Font = .body
    var lineLimit: Int? = nil
    var isSelectable = false

    var body: some View {
        if isSelectable {
            baseText
                .textSelection(.enabled)
        } else {
            baseText
        }
    }

    private var baseText: some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }
}
