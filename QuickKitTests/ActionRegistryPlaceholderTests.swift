import XCTest
@testable import QuickKit

/// Placeholder so the suite documents the registry boundary before Milestone 2.
final class ActionRegistryPlaceholderTests: XCTestCase {
    func testFileKindCasesExistForRegistry() {
        XCTAssertEqual(FileKind.allCases.count, 5)
        XCTAssertEqual(ActionRingMode.allCases.map(\.rawValue), ["conversion", "editing", "fileActions"])
    }
}
