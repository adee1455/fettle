import AppKit
import Foundation
import PDFKit
import XCTest
@testable import QuickKit

final class PDFServiceTests: XCTestCase {
    private var scratchDir: URL!
    private var pdfService: PDFService!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickKitPDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        pdfService = PDFService()
    }

    override func tearDownWithError() throws {
        if let scratchDir {
            try? FileManager.default.removeItem(at: scratchDir)
        }
        pdfService = nil
    }

    // MARK: - Helpers

    private func createSyntheticPDF(named name: String, pageCount: Int) throws -> URL {
        let url = scratchDir.appendingPathComponent(name)
        let doc = PDFDocument()
        for i in 0..<pageCount {
            let image = NSImage(size: NSSize(width: 200, height: 300), flipped: false) { rect in
                NSColor(srgbRed: 0.1 * Double(i + 1), green: 0.3, blue: 0.7, alpha: 1.0).setFill()
                rect.fill()
                return true
            }
            guard let page = PDFPage(image: image) else {
                throw XCTSkip("Could not create PDFPage")
            }
            doc.insert(page, at: i)
        }
        guard doc.write(to: url) else {
            throw XCTSkip("Could not write test PDF")
        }
        return url
    }

    private func createSyntheticImage(named name: String, width: Int = 120, height: Int = 80) throws -> URL {
        let url = scratchDir.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Could not create PNG data")
        }
        try pngData.write(to: url)
        return url
    }

    // MARK: - Tests

    func testMergePDFsCombinesPagesSequentially() throws {
        let pdf1 = try createSyntheticPDF(named: "part1.pdf", pageCount: 2)
        let pdf2 = try createSyntheticPDF(named: "part2.pdf", pageCount: 3)
        let outputURL = scratchDir.appendingPathComponent("merged.pdf")

        try pdfService.mergePDFs(sourceURLs: [pdf1, pdf2], destinationURL: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        guard let mergedDoc = PDFDocument(url: outputURL) else {
            return XCTFail("Could not reopen merged PDF")
        }
        XCTAssertEqual(mergedDoc.pageCount, 5)
    }

    func testImagesToPDFCreatesMultiPageDocument() throws {
        let img1 = try createSyntheticImage(named: "page1.png", width: 100, height: 150)
        let img2 = try createSyntheticImage(named: "page2.png", width: 200, height: 250)
        let outputURL = scratchDir.appendingPathComponent("fromImages.pdf")

        try pdfService.createPDF(fromImageURLs: [img1, img2], destinationURL: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        guard let doc = PDFDocument(url: outputURL) else {
            return XCTFail("Could not reopen generated PDF")
        }
        XCTAssertEqual(doc.pageCount, 2)
    }

    func testSplitPagesProducesSinglePageDocuments() throws {
        let multiPDF = try createSyntheticPDF(named: "multi.pdf", pageCount: 3)
        let outputDir = scratchDir.appendingPathComponent("SplitOutput", isDirectory: true)

        let generatedURLs = try pdfService.splitPages(sourceURL: multiPDF, destinationDirectory: outputDir)

        XCTAssertEqual(generatedURLs.count, 3)
        for (index, pageURL) in generatedURLs.enumerated() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: pageURL.path))
            guard let pageDoc = PDFDocument(url: pageURL) else {
                return XCTFail("Could not open page \(index + 1) PDF")
            }
            XCTAssertEqual(pageDoc.pageCount, 1)
        }
    }

    func testUnreadableOrEmptySourceThrows() throws {
        let emptyURL = scratchDir.appendingPathComponent("empty.pdf")
        try Data().write(to: emptyURL)

        let destURL = scratchDir.appendingPathComponent("out.pdf")
        XCTAssertThrowsError(try pdfService.mergePDFs(sourceURLs: [emptyURL], destinationURL: destURL))
    }

    // MARK: - JobManager Integration Tests

    @MainActor
    func testJobManagerExecutesMergePDFJob() async throws {
        let pdf1 = try createSyntheticPDF(named: "jobDoc1.pdf", pageCount: 1)
        let pdf2 = try createSyntheticPDF(named: "jobDoc2.pdf", pageCount: 2)

        let item1 = FileItem(url: pdf1, type: FileType(kind: .pdf, identifier: "com.adobe.pdf", localizedDescription: "PDF"))
        let item2 = FileItem(url: pdf2, type: FileType(kind: .pdf, identifier: "com.adobe.pdf", localizedDescription: "PDF"))

        let outputFolder = scratchDir.appendingPathComponent("JobOutput", isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let jobManager = JobManager(pdfService: pdfService)
        jobManager.outputFolderProvider = { outputFolder }

        let action = ConversionAction(
            id: "merge-pdfs",
            title: "Merge PDFs",
            subtitle: "Test",
            systemImage: "doc.on.doc",
            ringMode: .conversion,
            applicableKinds: [.pdf],
            requiredTool: nil,
            minSelection: 2,
            maxSelection: nil
        )

        let job = jobManager.enqueue(action: action, inputFiles: [item1, item2])

        for _ in 0..<50 {
            if job.status == .completed || job.status == .failed || job.status == .cancelled {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.outputURLs.count, 1)

        let outputDoc = try XCTUnwrap(job.outputURLs.first.flatMap { PDFDocument(url: $0) })
        XCTAssertEqual(outputDoc.pageCount, 3)
    }

    @MainActor
    func testJobManagerExecutesImagesToPDFJob() async throws {
        let img1 = try createSyntheticImage(named: "img1.png")
        let img2 = try createSyntheticImage(named: "img2.png")

        let item1 = FileItem(url: img1, type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG"))
        let item2 = FileItem(url: img2, type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG"))

        let outputFolder = scratchDir.appendingPathComponent("JobOutputImages", isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let jobManager = JobManager(pdfService: pdfService)
        jobManager.outputFolderProvider = { outputFolder }

        let action = ConversionAction(
            id: "images-to-pdf",
            title: "Images → PDF",
            subtitle: "Test",
            systemImage: "doc.richtext",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        )

        let job = jobManager.enqueue(action: action, inputFiles: [item1, item2])

        for _ in 0..<50 {
            if job.status == .completed || job.status == .failed || job.status == .cancelled {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.outputURLs.count, 1)

        let outputDoc = try XCTUnwrap(job.outputURLs.first.flatMap { PDFDocument(url: $0) })
        XCTAssertEqual(outputDoc.pageCount, 2)
    }

    @MainActor
    func testJobManagerExecutesSplitPDFPagesJob() async throws {
        let multiPDF = try createSyntheticPDF(named: "jobMulti.pdf", pageCount: 3)
        let item = FileItem(url: multiPDF, type: FileType(kind: .pdf, identifier: "com.adobe.pdf", localizedDescription: "PDF"))

        let outputFolder = scratchDir.appendingPathComponent("JobOutputSplit", isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let jobManager = JobManager(pdfService: pdfService)
        jobManager.outputFolderProvider = { outputFolder }

        let action = ConversionAction(
            id: "split-pdf-pages",
            title: "Split PDF Pages",
            subtitle: "Test",
            systemImage: "doc.badge.plus",
            ringMode: .conversion,
            applicableKinds: [.pdf],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: 1
        )

        let job = jobManager.enqueue(action: action, inputFiles: [item])

        for _ in 0..<50 {
            if job.status == .completed || job.status == .failed || job.status == .cancelled {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.outputURLs.count, 3)
    }
}
