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
            return try await inFlightTask.value
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
            throw error
        }
    }
}

private struct DefaultLocalTranslationClient: LocalTranslationClient {
    func translateEnglishToChinese(_ text: String) async throws -> String {
        if #available(macOS 26.0, *) {
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
