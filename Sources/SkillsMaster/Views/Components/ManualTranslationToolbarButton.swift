import SwiftUI

/// 统一的手动翻译工具栏按钮。
/// 保留 `translate` 图标，并通过高亮态提示当前是否正在显示译文。
struct ManualTranslationToolbarButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "translate")
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.18) : .clear)
                }
        }
        .help(isActive ? appLocalized("Show Original") : appLocalized("Translate Current Skill"))
    }
}
