import Foundation
import PDFKit
import XCTest
@testable import Fettle

final class DocumentServiceTests: XCTestCase {
    private var tempDir: URL!
    private var service: DocumentService!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentServiceTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = DocumentService()
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testConvertTextToPDFGeneratesValidPDF() async throws {
        let textFile = tempDir.appendingPathComponent("notes.txt")
        let textContent = """
        Fettle Smart Document Conversion
        ===================================
        This is a test of document-to-pdf conversion.
        Features tested:
        - CoreText multi-page layout
        - Clean typography
        - Zero external dependencies
        """
        try textContent.write(to: textFile, atomically: true, encoding: .utf8)

        let destPDF = tempDir.appendingPathComponent("notes.pdf")
        try await service.convertToPDF(sourceURL: textFile, destinationURL: destPDF)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destPDF.path))
        let pdf = PDFDocument(url: destPDF)
        XCTAssertNotNil(pdf)
        XCTAssertGreaterThan(pdf?.pageCount ?? 0, 0)
    }

    func testConvertPresentationToPDFGeneratesValidPDF() async throws {
        let pptxFile = tempDir.appendingPathComponent("quarterly_report.pptx")
        let dummyData = "PK\u{03}\u{04}sample presentation content slide 1 slide 2".data(using: .utf8)!
        try dummyData.write(to: pptxFile)

        let destPDF = tempDir.appendingPathComponent("quarterly_report.pdf")
        try await service.convertToPDF(sourceURL: pptxFile, destinationURL: destPDF)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destPDF.path))
        let pdf = PDFDocument(url: destPDF)
        XCTAssertNotNil(pdf)
        XCTAssertGreaterThan(pdf?.pageCount ?? 0, 0)
    }

    @MainActor
    func testJobManagerExecutesDocumentToPDFJob() async throws {
        let docFile = tempDir.appendingPathComponent("brief.md")
        try "Project Brief\nStatus: Active".write(to: docFile, atomically: true, encoding: .utf8)

        let jobManager = JobManager(documentService: service)
        jobManager.outputFolderProvider = { self.tempDir }

        let item = FileItem(
            url: docFile,
            type: FileType(kind: .document, identifier: "net.daringfireball.markdown", localizedDescription: "Markdown")
        )
        let action = ConversionAction(
            id: "document-to-pdf",
            title: "Convert to PDF",
            subtitle: "Standardized document format",
            systemImage: "doc.richtext",
            ringMode: .conversion,
            applicableKinds: [.document],
            isSuggested: true,
            priority: 10,
            targetFormat: "PDF"
        )

        let job = jobManager.enqueue(action: action, inputFiles: [item])

        // Wait for job completion
        for _ in 0..<40 {
            if job.status == .completed || job.status == .failed { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.outputURLs.count, 1)
        if let out = job.outputURLs.first {
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
            XCTAssertEqual(out.pathExtension, "pdf")
        }
    }
}
