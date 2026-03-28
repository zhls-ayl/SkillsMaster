import XCTest
@testable import SkillsMaster

final class TranslationServiceTests: XCTestCase {

    private actor FakeClient: LocalTranslationClient {
        private(set) var calls: [String] = []
        let result: String

        init(result: String) {
            self.result = result
        }

        func translateEnglishToChinese(_ text: String) async throws -> String {
            calls.append(text)
            return result
        }
    }

    private actor SlowFakeClient: LocalTranslationClient {
        private(set) var calls: [String] = []
        private(set) var activeCallCount = 0
        private(set) var maxConcurrentCallCount = 0
        let delayNanoseconds: UInt64

        init(delayNanoseconds: UInt64 = 50_000_000) {
            self.delayNanoseconds = delayNanoseconds
        }

        func translateEnglishToChinese(_ text: String) async throws -> String {
            calls.append(text)
            activeCallCount += 1
            maxConcurrentCallCount = max(maxConcurrentCallCount, activeCallCount)
            defer { activeCallCount -= 1 }

            try await Task.sleep(nanoseconds: delayNanoseconds)
            return "ZH:\(text)"
        }
    }

    func testTranslateEnglishToChinese_cachesByExactText() async throws {
        let client = FakeClient(result: "你好")
        let service = TranslationService(client: client)

        let first = try await service.translateEnglishToChinese("Hello")
        let second = try await service.translateEnglishToChinese("Hello")

        XCTAssertEqual(first, "你好")
        XCTAssertEqual(second, "你好")

        let calls = await client.calls
        XCTAssertEqual(calls, ["Hello"])
    }

    func testTranslateEnglishToChinese_deduplicatesConcurrentRequestsForSameText() async throws {
        let client = SlowFakeClient()
        let service = TranslationService(client: client)

        async let first = service.translateEnglishToChinese("Hello")
        async let second = service.translateEnglishToChinese("Hello")

        let results = try await [first, second]
        XCTAssertEqual(results, ["ZH:Hello", "ZH:Hello"])

        let calls = await client.calls
        XCTAssertEqual(calls, ["Hello"])
    }

    func testTranslateEnglishToChinese_serializesDifferentTexts() async throws {
        let client = SlowFakeClient()
        let service = TranslationService(client: client)

        async let first = service.translateEnglishToChinese("One")
        async let second = service.translateEnglishToChinese("Two")

        let results = try await [first, second]
        XCTAssertEqual(results, ["ZH:One", "ZH:Two"])

        let calls = await client.calls
        XCTAssertEqual(calls, ["One", "Two"])
        let maxConcurrent = await client.maxConcurrentCallCount
        XCTAssertEqual(maxConcurrent, 1)
    }

    func testTranslateEnglishToChinese_mapsOfflineModelFailureToUnavailable() async {
        actor OfflineModelsUnavailableClient: LocalTranslationClient {
            func translateEnglishToChinese(_ text: String) async throws -> String {
                throw NSError(
                    domain: "TranslationErrorDomain",
                    code: 16,
                    userInfo: [
                        NSLocalizedFailureReasonErrorKey: "Offline models not available for language pair"
                    ]
                )
            }
        }

        let service = TranslationService(client: OfflineModelsUnavailableClient())

        do {
            _ = try await service.translateEnglishToChinese("Hello")
            XCTFail("Expected unavailable error")
        } catch let error as TranslationService.TranslationError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Expected TranslationError.unavailable, got \(error)")
        }
    }

    func testTranslateEnglishToChinese_mapsLocalizedOfflineModelFailureToUnavailable() async {
        actor OfflineModelsUnavailableClient: LocalTranslationClient {
            func translateEnglishToChinese(_ text: String) async throws -> String {
                throw NSError(
                    domain: "TranslationErrorDomain",
                    code: 16,
                    userInfo: [
                        NSLocalizedFailureReasonErrorKey: "当前语言对缺少离线模型"
                    ]
                )
            }
        }

        let service = TranslationService(client: OfflineModelsUnavailableClient())

        do {
            _ = try await service.translateEnglishToChinese("Hello")
            XCTFail("Expected unavailable error")
        } catch let error as TranslationService.TranslationError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Expected TranslationError.unavailable, got \(error)")
        }
    }

    func testTranslateEnglishToChinese_mapsConcurrentOfflineModelFailureToUnavailable() async {
        actor OfflineModelsUnavailableClient: LocalTranslationClient {
            func translateEnglishToChinese(_ text: String) async throws -> String {
                try? await Task.sleep(nanoseconds: 20_000_000)
                throw NSError(
                    domain: "TranslationErrorDomain",
                    code: 16,
                    userInfo: [
                        NSLocalizedFailureReasonErrorKey: "Offline models not available for language pair"
                    ]
                )
            }
        }

        let service = TranslationService(client: OfflineModelsUnavailableClient())

        async let first = captureResult {
            try await service.translateEnglishToChinese("Hello")
        }
        async let second = captureResult {
            try await service.translateEnglishToChinese("Hello")
        }

        let results = await [first, second]
        XCTAssertEqual(results.count, 2)

        for result in results {
            switch result {
            case .success:
                XCTFail("Expected unavailable error")
            case .failure(let error as TranslationService.TranslationError):
                if case .unavailable = error {
                    continue
                }
                XCTFail("Expected TranslationError.unavailable, got \(error)")
            case .failure(let error):
                XCTFail("Expected TranslationError.unavailable, got \(error)")
            }
        }
    }

    private func captureResult(
        _ operation: @escaping () async throws -> String
    ) async -> Result<String, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}
