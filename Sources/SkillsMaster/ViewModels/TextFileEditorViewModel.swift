import Foundation

@MainActor
@Observable
final class TextFileEditorViewModel {

    let fileURL: URL
    let fileKind: TextEditableFileKind

    var text = ""
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    @ObservationIgnored private var originalText = ""
    @ObservationIgnored private var hasLoadedOnce = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileKind = TextEditableFileKind.from(url: fileURL) ?? .plainText
    }

    var displayName: String {
        fileURL.lastPathComponent
    }

    var hasUnsavedChanges: Bool {
        text != originalText
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
            let content = try await Task.detached(priority: .userInitiated) {
                try TextFileLoader.readText(from: fileURL)
            }.value

            guard !Task.isCancelled else { return }
            text = content
            originalText = content
            hasLoadedOnce = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }

        if !Task.isCancelled {
            isLoading = false
        }
    }

    func save() async -> Bool {
        guard hasLoadedOnce else { return false }

        isSaving = true
        errorMessage = nil
        let currentText = text
        let fileURL = self.fileURL

        do {
            try await Task.detached(priority: .userInitiated) {
                try currentText.write(to: fileURL, atomically: true, encoding: .utf8)
            }.value

            guard !Task.isCancelled else { return false }
            originalText = currentText
            isSaving = false
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = error.localizedDescription
            isSaving = false
            return false
        }
    }

    func discardChanges() {
        text = originalText
    }
}
