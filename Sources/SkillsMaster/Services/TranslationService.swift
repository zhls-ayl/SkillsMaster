import Foundation

#if canImport(Translation)
import Translation
#endif

protocol EnglishToChineseTranslating: Sendable {
    func translateEnglishToChinese(_ text: String) async throws -> String
}

protocol LocalTranslationPreparationClient: Sendable {
    func prepareEnglishToChineseIfNeeded() async throws
}

protocol LocalTranslationClient: Sendable {
    func translateEnglishToChinese(_ text: String) async throws -> String
}

actor TranslationService: EnglishToChineseTranslating {

    enum TranslationError: Error {
        case unavailable
    }

    private let client: any LocalTranslationClient
    private let preparationClient: any LocalTranslationPreparationClient
    private var cache: [String: String] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]
    private var serialTailTask: Task<Void, Never>?

    init(
        client: any LocalTranslationClient = DefaultLocalTranslationClient(),
        preparationClient: any LocalTranslationPreparationClient = DefaultLocalTranslationPreparationClient()
    ) {
        self.client = client
        self.preparationClient = preparationClient
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
        let task = Task<String, Error> { [client, preparationClient] in
            _ = await previousTask?.result
            try await preparationClient.prepareEnglishToChineseIfNeeded()
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

private struct DefaultLocalTranslationPreparationClient: LocalTranslationPreparationClient {
    func prepareEnglishToChineseIfNeeded() async throws {
        if #available(macOS 26.0, *), TranslationPlatformSupport.canPerformInlineTranslation {
            #if canImport(Translation) && compiler(>=6.2)
            try await TranslationSessionWarmup.shared.prepareEnglishToChineseIfNeeded()
            #endif
        }
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
private actor TranslationSessionWarmup {
    static let shared = TranslationSessionWarmup()

    private var isPrepared = false
    private var inFlight: Task<Void, Error>?

    func prepareEnglishToChineseIfNeeded() async throws {
        if isPrepared {
            return
        }

        if let inFlight {
            return try await inFlight.value
        }

        let task = Task<Void, Error> {
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )

            if !(await session.isReady) {
                try await session.prepareTranslation()
            }
        }
        inFlight = task

        do {
            try await task.value
            isPrepared = true
            inFlight = nil
        } catch {
            inFlight = nil
            throw error
        }
    }
}

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
