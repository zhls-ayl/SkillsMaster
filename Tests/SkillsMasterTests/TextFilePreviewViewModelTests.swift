import XCTest
@testable import SkillsMaster

@MainActor
final class TextFilePreviewViewModelTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsMaster-PreviewVM-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testReusingIfPossiblePreservesLoadedPreviewForSameFile() async throws {
        let fileURL = tempDirectory.appendingPathComponent("settings.json")
        try #"{"b":1,"a":2}"#.write(to: fileURL, atomically: true, encoding: .utf8)

        let initialViewModel = TextFilePreviewViewModel(fileURL: fileURL)
        await initialViewModel.loadIfNeeded()

        let reusedViewModel = TextFilePreviewViewModel.reusingIfPossible(
            initialViewModel,
            for: fileURL
        )

        XCTAssertTrue(initialViewModel === reusedViewModel)
        XCTAssertEqual(
            reusedViewModel.previewContent?.text,
            """
            {
              "a" : 2,
              "b" : 1
            }
            """
        )
    }

    func testReusingIfPossibleCreatesNewPreviewForDifferentFile() async throws {
        let firstFileURL = tempDirectory.appendingPathComponent("settings.json")
        try #"{"hello":"world"}"#.write(to: firstFileURL, atomically: true, encoding: .utf8)

        let secondFileURL = tempDirectory.appendingPathComponent("README.md")
        try "# Title".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let initialViewModel = TextFilePreviewViewModel(fileURL: firstFileURL)
        await initialViewModel.loadIfNeeded()

        let newViewModel = TextFilePreviewViewModel.reusingIfPossible(
            initialViewModel,
            for: secondFileURL
        )

        XCTAssertFalse(initialViewModel === newViewModel)
        XCTAssertEqual(newViewModel.fileURL.standardizedFileURL, secondFileURL.standardizedFileURL)
        XCTAssertNil(newViewModel.previewContent)
    }
}
