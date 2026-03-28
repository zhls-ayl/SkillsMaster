import SwiftUI

struct TextFileEditorView: View {

    @Bindable var viewModel: TextFileEditorViewModel
    let onSave: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if viewModel.isLoading {
                ProgressView("Loading \(viewModel.displayName)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(viewModel.fileKind.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if viewModel.hasUnsavedChanges {
                            Label("Unsaved", systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    TextEditor(text: $viewModel.text)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: viewModel.fileURL) {
            viewModel.loadIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayName)
                    .font(.headline)
                Text(viewModel.fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                Task { await onSave() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isLoading || viewModel.isSaving || !viewModel.hasUnsavedChanges)
        }
        .padding(16)
    }
}
