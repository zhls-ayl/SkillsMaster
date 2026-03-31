import SwiftUI

struct TextFilePreviewView: View {

    @Bindable var viewModel: TextFilePreviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = viewModel.previewContent?.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoading && viewModel.previewContent == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(appLocalized("Loading preview..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let previewContent = viewModel.previewContent {
                switch previewContent.style {
                case .markdown:
                    MarkdownContentView(markdownText: previewContent.text)
                case .code(let language):
                    CodePreviewCard(text: previewContent.text, language: language)
                }
            }
        }
        .task(id: ObjectIdentifier(viewModel)) {
            await viewModel.loadIfNeeded()
        }
    }
}

private struct CodePreviewCard: View {
    let text: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, language == nil ? 12 : 0)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
