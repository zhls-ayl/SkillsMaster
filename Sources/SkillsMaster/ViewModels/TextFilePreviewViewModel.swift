import Foundation

@MainActor
@Observable
final class TextFilePreviewViewModel {

    let fileURL: URL
    let fileKind: TextEditableFileKind

    var previewContent: TextFilePreviewContent?
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private var hasLoadedOnce = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileKind = TextEditableFileKind.from(url: fileURL) ?? .plainText
    }

    func loadIfNeeded() {
        guard !hasLoadedOnce else { return }
        Task { await load() }
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            let fileURL = self.fileURL
            let fileKind = self.fileKind

            let previewContent = try await Task.detached(priority: .userInitiated) {
                let loaded = try TextFileLoader.loadText(from: fileURL)
                return TextFilePreviewFormatter.makePreview(
                    text: loaded.text,
                    kind: fileKind,
                    fileSize: loaded.fileSize
                )
            }.value

            guard !Task.isCancelled else { return }
            self.previewContent = previewContent
            hasLoadedOnce = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        if !Task.isCancelled {
            isLoading = false
        }
    }
}
