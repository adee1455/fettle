import UniformTypeIdentifiers
import XCTest
@testable import Fettle

final class FileTypeDetectorTests: XCTestCase {
    private let detector = FileTypeDetector()
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FettleFileType-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    func testPNGIsImage() throws {
        let url = scratch.appendingPathComponent("sample.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: url)
        let type = detector.detect(url: url)
        XCTAssertEqual(type.kind, .image)
        XCTAssertTrue(type.identifier.contains("png") || type.identifier.contains("image"))
    }

    func testJPEGIsImage() throws {
        let url = scratch.appendingPathComponent("photo.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: url)
        XCTAssertEqual(detector.detect(url: url).kind, .image)
    }

    func testPDFIsPDF() throws {
        let url = scratch.appendingPathComponent("doc.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: url)
        XCTAssertEqual(detector.detect(url: url).kind, .pdf)
    }

    func testMP3IsAudio() throws {
        let url = scratch.appendingPathComponent("track.mp3")
        try Data([0xFF, 0xFB]).write(to: url)
        let type = detector.detect(url: url)
        XCTAssertEqual(type.kind, .audio)
    }

    func testMP4IsVideo() throws {
        let url = scratch.appendingPathComponent("clip.mp4")
        try Data(count: 16).write(to: url)
        let type = detector.detect(url: url)
        XCTAssertEqual(type.kind, .video)
    }

    func testPPTXIsDocument() throws {
        let url = scratch.appendingPathComponent("deck.pptx")
        try Data("PK0304".utf8).write(to: url)
        let type = detector.detect(url: url)
        XCTAssertEqual(type.kind, .document)
    }

    func testDOCXIsDocument() throws {
        let url = scratch.appendingPathComponent("doc.docx")
        try Data("PK0304".utf8).write(to: url)
        let type = detector.detect(url: url)
        XCTAssertEqual(type.kind, .document)
    }

    func testClassifyUsesUTType() {
        let png = detector.classify(utType: .png, fallbackUTI: nil)
        XCTAssertEqual(png.kind, .image)
        let pdf = detector.classify(utType: .pdf, fallbackUTI: nil)
        XCTAssertEqual(pdf.kind, .pdf)
        let unknown = detector.classify(utType: nil, fallbackUTI: "public.data")
        XCTAssertEqual(unknown.kind, .other)
        XCTAssertEqual(unknown.identifier, "public.data")
    }

    func testUnicodePath() throws {
        let url = scratch.appendingPathComponent("截图 1.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        XCTAssertEqual(detector.detect(url: url).kind, .image)
    }
}
