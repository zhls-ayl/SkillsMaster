import Foundation

#if canImport(Translation)
import Translation
#endif

protocol LocalTranslationClient: Sendable {
    func translateEnglishToChinese(_ text: String) async throws -> String
}

actor TranslationService {

    enum TranslationError: Error {
        case unavailable
    }

    private let client: any LocalTranslationClient
    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]
    private var serialTailTask: Task<Void, Never>?

    init(client: any LocalTranslationClient = DefaultLocalTranslationClient()) {
        self.client = client
    }

    func translateEnglishToChinese(_ text: String) async throws -> String {
        if let cached = cache[text] {
            return cached
        }

        if let inFlightTask = inFlight[text] {
            do {
                return try await inFlightTask.value
            } catch {
                throw normalize(error: error)
            }
        }

        let previousTask = serialTailTask
        let task = Task<String, Error> { [client] in
            _ = await previousTask?.result
            return try await client.translateEnglishToChinese(text)
        }
        inFlight[text] = task
        serialTailTask = Task {
            _ = await task.result
        }

        do {
            let translated = try await task.value
            cache[text] = translated
            inFlight[text] = nil
            return translated
        } catch {
            inFlight[text] = nil
            throw normalize(error: error)
        }
    }

    private func normalize(error: Error) -> Error {
        if error is CancellationError {
            return error
        }

        if error as? TranslationError == .unavailable {
            return TranslationError.unavailable
        }

        let nsError = error as NSError
        if nsError.domain == "TranslationErrorDomain",
           nsError.code == 16 {
            return TranslationError.unavailable
        }

        return error
    }
}

private struct DefaultLocalTranslationClient: LocalTranslationClient {
    func translateEnglishToChinese(_ text: String) async throws -> String {
        if #available(macOS 26.0, *), TranslationPlatformSupport.canPerformInlineTranslation {
            #if canImport(Translation) && compiler(>=6.2)
            return try await TranslationFrameworkClient().translateEnglishToChinese(text)
            #else
            throw TranslationService.TranslationError.unavailable
            #endif
        }

        throw TranslationService.TranslationError.unavailable
    }
}

#if canImport(Translation) && compiler(>=6.2)
@available(macOS 26.0, *)
private struct TranslationFrameworkClient: LocalTranslationClient {
    func translateEnglishToChinese(_ text: String) async throws -> String {
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "zh-Hans")
        )
        let response = try await session.translate(text)
        return response.targetText
    }
}
#endif
