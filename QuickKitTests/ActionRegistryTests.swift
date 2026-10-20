import XCTest
@testable import QuickKit

final class ActionRegistryTests: XCTestCase {
    private let registry = ActionRegistry()

    func testFileKindCasesExistForRegistry() {
        XCTAssertEqual(FileKind.allCases.count, 6)
        XCTAssertEqual(ActionRingMode.allCases.map(\.rawValue), ["conversion", "editing", "fileActions"])
    }

    func testEmptySelectionReturnsNoActions() {
        let actions = registry.actions(for: [], toolStatuses: [:])
        XCTAssertTrue(actions.isEmpty)
    }

    func testImageActionsForSinglePNG() {
        let png = FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        let actions = registry.actions(for: [png], toolStatuses: [:])

        XCTAssertFalse(actions.isEmpty)
        let ids = actions.map(\.id)
        XCTAssertTrue(ids.contains("png-to-jpeg"))
        XCTAssertTrue(ids.contains("image-to-webp"))
        XCTAssertTrue(ids.contains("images-to-pdf"))
        XCTAssertTrue(ids.contains("resize-50"))
        XCTAssertTrue(ids.contains("reveal-in-finder"))

        // Smart relatable filtering: JPEG -> PNG must NOT be suggested for a PNG file!
        XCTAssertFalse(ids.contains("jpeg-to-png"))

        // Video and PDF actions must NOT appear
        XCTAssertFalse(ids.contains("video-to-mp4-h264"))
        XCTAssertFalse(ids.contains("merge-pdfs"))

        // Priority ordering: WebP first, then JPEG, then PDF
        let webpIndex = ids.firstIndex(of: "image-to-webp")!
        let jpegIndex = ids.firstIndex(of: "png-to-jpeg")!
        let pdfIndex = ids.firstIndex(of: "images-to-pdf")!
        XCTAssertLessThan(webpIndex, jpegIndex)
        XCTAssertLessThan(jpegIndex, pdfIndex)
    }

    func testDocumentActionsForPPTX() {
        let pptx = FileItem(
            url: URL(fileURLWithPath: "/tmp/slides.pptx"),
            type: FileType(kind: .document, identifier: "org.openxmlformats.presentationml.presentation", localizedDescription: "Presentation")
        )
        let actions = registry.actions(for: [pptx], toolStatuses: [:])
        let ids = actions.map(\.id)
        XCTAssertTrue(ids.contains("document-to-pdf"))
        XCTAssertTrue(ids.contains("reveal-in-finder"))
        XCTAssertFalse(ids.contains("png-to-jpeg"))
        XCTAssertFalse(ids.contains("video-to-mp4-h264"))

        // Document to PDF must be suggested and top priority
        XCTAssertEqual(ids.first, "document-to-pdf")
    }

    func testMergePDFRequiresMinTwo() {
        let pdf1 = FileItem(
            url: URL(fileURLWithPath: "/tmp/doc1.pdf"),
            type: FileType(kind: .pdf, identifier: "com.adobe.pdf", localizedDescription: "PDF")
        )
        let pdf2 = FileItem(
            url: URL(fileURLWithPath: "/tmp/doc2.pdf"),
            type: FileType(kind: .pdf, identifier: "com.adobe.pdf", localizedDescription: "PDF")
        )

        // Single PDF
        let singleActions = registry.actions(for: [pdf1], toolStatuses: [:])
        XCTAssertFalse(singleActions.map(\.id).contains("merge-pdfs"))

        // Two PDFs
        let twoActions = registry.actions(for: [pdf1, pdf2], toolStatuses: [:])
        XCTAssertTrue(twoActions.map(\.id).contains("merge-pdfs"))
    }

    func testVideoActionsHiddenWithoutFFmpeg() {
        let video = FileItem(
            url: URL(fileURLWithPath: "/tmp/clip.mp4"),
            type: FileType(kind: .video, identifier: "public.mpeg-4", localizedDescription: "MPEG-4")
        )

        let actionsMissing = registry.actions(for: [video], toolStatuses: [.ffmpeg: .missing])
        let missingIds = actionsMissing.map(\.id)
        XCTAssertFalse(missingIds.contains("video-to-mp4-hevc"))
        XCTAssertFalse(missingIds.contains("extract-audio-mp3"))
        // video-to-mp4-h264 is supported via AVFoundation fallback
        XCTAssertTrue(missingIds.contains("video-to-mp4-h264"))

        let actionsIncompatible = registry.actions(
            for: [video],
            toolStatuses: [.ffmpeg: .incompatibleArchitecture(url: URL(fileURLWithPath: "/usr/local/bin/ffmpeg"), architecture: .x86_64)]
        )
        let incompIds = actionsIncompatible.map(\.id)
        XCTAssertFalse(incompIds.contains("video-to-mp4-hevc"))
        XCTAssertFalse(incompIds.contains("extract-audio-mp3"))
        XCTAssertTrue(incompIds.contains("video-to-mp4-h264"))
    }

    func testVideoActionsShownWithFFmpeg() {
        let video = FileItem(
            url: URL(fileURLWithPath: "/tmp/clip.mp4"),
            type: FileType(kind: .video, identifier: "public.mpeg-4", localizedDescription: "MPEG-4")
        )

        let actions = registry.actions(
            for: [video],
            toolStatuses: [.ffmpeg: .available(url: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), architecture: .arm64)]
        )
        let ids = actions.map(\.id)
        XCTAssertTrue(ids.contains("video-to-mp4-h264"))
        XCTAssertTrue(ids.contains("video-to-mp4-hevc"))
        XCTAssertTrue(ids.contains("extract-audio-mp3"))
    }

    func testMixedSelectionFiltersCorrectly() {
        let png = FileItem(
            url: URL(fileURLWithPath: "/tmp/sample.png"),
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )
        let pdf = FileItem(
            url: URL(fileURLWithPath: "/tmp/doc.pdf"),
            type: FileType(kind: .pdf, identifier: "com.adobe.pdf", localizedDescription: "PDF")
        )

        let actions = registry.actions(for: [png, pdf], toolStatuses: [:])
        let ids = Set(actions.map(\.id))

        // Image-specific actions must NOT appear
        XCTAssertFalse(ids.contains("png-to-jpeg"))
        XCTAssertFalse(ids.contains("resize-50"))
        XCTAssertFalse(ids.contains("images-to-pdf"))

        // PDF-specific actions must NOT appear
        XCTAssertFalse(ids.contains("merge-pdfs"))
        XCTAssertFalse(ids.contains("split-pdf-pages"))

        // Only universal file actions should survive
        XCTAssertTrue(ids.contains("reveal-in-finder"))
        XCTAssertTrue(ids.contains("copy-path"))
        XCTAssertTrue(ids.contains("duplicate-file"))
    }

    func testFileActionsApplyToAllKinds() {
        for kind in FileKind.allCases {
            let item = FileItem(
                url: URL(fileURLWithPath: "/tmp/item.\(kind.rawValue)"),
                type: FileType(kind: kind, identifier: "test.\(kind.rawValue)", localizedDescription: "Test")
            )
            let actions = registry.actions(for: [item], toolStatuses: [:], ringMode: .fileActions)
            let ids = Set(actions.map(\.id))
            XCTAssertTrue(ids.contains("reveal-in-finder"), "Expected reveal-in-finder for \(kind)")
            XCTAssertTrue(ids.contains("copy-path"), "Expected copy-path for \(kind)")
            XCTAssertTrue(ids.contains("duplicate-file"), "Expected duplicate-file for \(kind)")
        }
    }
}
