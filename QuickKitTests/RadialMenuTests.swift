import AppKit
import Foundation
import XCTest
@testable import QuickKit

@MainActor
final class RadialMenuTests: XCTestCase {
    private var appState: AppState!

    override func setUp() {
        super.setUp()
        appState = AppState()
    }

    override func tearDown() {
        appState.closeRadialMenu()
        appState = nil
        super.tearDown()
    }

    // MARK: - Geometry Tests

    func testRadialGeometryDistribution() {
        let total = 6
        let radius: CGFloat = 112.0
        let step = (2.0 * CGFloat.pi) / CGFloat(total)

        for i in 0..<total {
            let angle = -CGFloat.pi / 2.0 + CGFloat(i) * step
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            // Distance from center must equal radius
            let computedRadius = sqrt(x * x + y * y)
            XCTAssertEqual(computedRadius, radius, accuracy: 0.001)

            // First item must be at top (angle = -pi/2 => x = 0, y = -radius)
            if i == 0 {
                XCTAssertEqual(x, 0, accuracy: 0.001)
                XCTAssertEqual(y, -radius, accuracy: 0.001)
            }
        }
    }

    // MARK: - Mode & Action Resolution Tests

    func testRadialActionResolutionPerRingMode() {
        let png = FileItem(
            url: URL(fileURLWithPath: "/tmp/test.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        appState.items = [png]

        // Conversion mode
        let convActions = appState.availableActions(ringMode: .conversion)
        let convIds = convActions.map(\.id)
        XCTAssertTrue(convIds.contains("png-to-jpeg"))
        XCTAssertTrue(convIds.contains("image-to-webp"))
        XCTAssertFalse(convIds.contains("resize-50"))

        // Editing mode
        let editActions = appState.availableActions(ringMode: .editing)
        let editIds = editActions.map(\.id)
        XCTAssertTrue(editIds.contains("resize-50"))
        XCTAssertTrue(editIds.contains("strip-metadata"))
        XCTAssertFalse(editIds.contains("png-to-jpeg"))

        // File Actions mode
        let fileActions = appState.availableActions(ringMode: .fileActions)
        let fileIds = fileActions.map(\.id)
        XCTAssertTrue(fileIds.contains("reveal-in-finder"))
        XCTAssertTrue(fileIds.contains("copy-path"))
        XCTAssertTrue(fileIds.contains("duplicate-file"))
        XCTAssertFalse(fileIds.contains("resize-50"))
    }

    // MARK: - Invocation & Dismissal Tests

    func testRadialMenuOpenWithoutItemsShowsStatusMessage() {
        appState.items = []
        appState.selectedItemIDs = []

        appState.openRadialMenuForSelection(mode: .conversion)
        XCTAssertEqual(appState.statusMessage, "Select or load files first to open Radial Menu.")
    }

    func testRadialMenuOpenAndCloseLifecycle() {
        let png = FileItem(
            url: URL(fileURLWithPath: "/tmp/test.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        appState.items = [png]

        appState.openRadialMenuForSelection(mode: .conversion)
        appState.closeRadialMenu()

        XCTAssertNil(appState.dragMonitor.latchedMode)
    }

    func testRadialActionExecutionEnqueuesJob() {
        let png = FileItem(
            url: URL(fileURLWithPath: "/tmp/test.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        appState.items = [png]

        let action = ConversionAction(
            id: "copy-path",
            title: "Copy Path",
            subtitle: "Test",
            systemImage: "doc.on.clipboard",
            ringMode: .fileActions,
            applicableKinds: Set(FileKind.allCases),
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        )

        appState.runAction(action)
        XCTAssertEqual(appState.jobManager.jobs.count, 1)
        XCTAssertEqual(appState.jobManager.jobs.first?.action.id, "copy-path")
    }

    func testRadialConversionRunsExclusivelyOnDraggedTargetsNotHistory() {
        let oldItem = FileItem(
            url: URL(fileURLWithPath: "/tmp/old_image.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        appState.items = [oldItem]

        let newlyDraggedItem = FileItem(
            url: URL(fileURLWithPath: "/tmp/new_presentation.pptx"),
            type: FileType(kind: .document, identifier: "org.openxmlformats.presentationml.presentation", localizedDescription: "Presentation")
        )

        let action = ConversionAction(
            id: "document-to-pdf",
            title: "Convert to PDF",
            subtitle: "Test",
            systemImage: "doc.richtext",
            ringMode: .conversion,
            applicableKinds: [.document],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        )

        // Run action strictly on newlyDraggedItem
        appState.runAction(action, targets: [newlyDraggedItem])

        XCTAssertEqual(appState.jobManager.jobs.count, 1)
        let job = appState.jobManager.jobs.first!
        XCTAssertEqual(job.inputFiles.count, 1)
        XCTAssertEqual(job.inputFiles.first?.url.path, "/tmp/new_presentation.pptx")
        XCTAssertFalse(job.inputFiles.contains(where: { $0.url.path == "/tmp/old_image.png" }))
    }

    func testRadialMenuClosesAndClearsSnapshotOnEscape() {
        let png = FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        appState.items = [png]
        appState.openRadialMenuForSelection(mode: .conversion)

        // Trigger onEscape closure
        appState.dragMonitor.onEscape()

        XCTAssertNil(appState.dragMonitor.latchedMode)
        XCTAssertTrue(appState.dragMonitor.snapshotURLs.isEmpty)
    }
}
