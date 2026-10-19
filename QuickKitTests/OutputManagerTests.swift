import XCTest
@testable import QuickKit

final class OutputManagerTests: XCTestCase {
    private var scratchDir: URL!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("QuickKitOutputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratchDir {
            try? FileManager.default.removeItem(at: scratchDir)
        }
    }

    func testDefaultOutputFolderResolvesDownloads() {
        let settings = AppSettings()
        let resolved = OutputManager.resolvedOutputFolder(from: settings)
        XCTAssertTrue(resolved.path.contains("QuickKit Output"))
    }

    func testNonCollidingURLWhenNoConflict() {
        let url = OutputManager.nonCollidingURL(for: "result", extension: "png", in: scratchDir)
        XCTAssertEqual(url.lastPathComponent, "result.png")
    }

    func testNonCollidingURLWhenConflictExists() throws {
        let existing = scratchDir.appendingPathComponent("photo.jpg")
        try Data("dummy".utf8).write(to: existing)

        let candidate1 = OutputManager.nonCollidingURL(for: "photo", extension: "jpg", in: scratchDir)
        XCTAssertEqual(candidate1.lastPathComponent, "photo (1).jpg")

        try Data("dummy2".utf8).write(to: candidate1)
        let candidate2 = OutputManager.nonCollidingURL(for: "photo", extension: "jpg", in: scratchDir)
        XCTAssertEqual(candidate2.lastPathComponent, "photo (2).jpg")
    }

    func testNonCollidingURLWithoutExtension() throws {
        let existing = scratchDir.appendingPathComponent("archive")
        try Data("dummy".utf8).write(to: existing)

        let candidate = OutputManager.nonCollidingURL(for: "archive", extension: "", in: scratchDir)
        XCTAssertEqual(candidate.lastPathComponent, "archive (1)")
    }
}
