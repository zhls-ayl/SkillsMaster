import SwiftUI

/// 展示 frontmatter 中未在主信息区出现的额外字段。
struct SkillFrontmatterView: View {
    let fields: [FrontmatterField]
    var title: String? = nil

    var body: some View {
        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.headline)
                } else {
                    Text(appLocalized("Skill Metadata"))
                        .font(.headline)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(fields, id: \.key) { field in
                        GridRow(alignment: .top) {
                            Text(field.key)
                                .foregroundStyle(.secondary)

                            fieldValueView(field.value)
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func fieldValueView(_ value: String) -> some View {
        if value.contains("\n") || value.count > 100 {
            Text(verbatim: value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 6))
        } else {
            Text(verbatim: value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
