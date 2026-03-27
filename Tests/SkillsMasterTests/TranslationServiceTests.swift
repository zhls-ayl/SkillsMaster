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
}
