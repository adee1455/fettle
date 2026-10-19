import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import QuickKit

final class ImageServiceTests: XCTestCase {
    private var scratchDir: URL!
    private var imageService: ImageService!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickKitImageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        imageService = ImageService()
    }

    override func tearDownWithError() throws {
        if let scratchDir {
            try? FileManager.default.removeItem(at: scratchDir)
        }
        imageService = nil
    }

    // MARK: - Synthetic Fixture Helper

    private func createSyntheticImage(
        named name: String,
        width: Int,
        height: Int,
        hasAlpha: Bool = true,
        exifComment: String? = nil
    ) throws -> URL {
        let url = scratchDir.appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw XCTSkip("Could not create CGContext")
        }

        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: hasAlpha ? 0.5 : 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            throw XCTSkip("Could not make CGImage")
        }

        let utType = name.hasSuffix(".jpg") ? UTType.jpeg : UTType.png
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, utType.identifier as CFString, 1, nil) else {
            throw XCTSkip("Could not create CGImageDestination")
        }

        var properties: [CFString: Any] = [:]
        if let exifComment {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifUserComment: exifComment
            ]
        }

        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw XCTSkip("Could not finalize test fixture")
        }
        return url
    }

    // MARK: - Format Conversion Tests

    func testPNGToJPEGConversion() async throws {
        let sourceURL = try createSyntheticImage(named: "input.png", width: 100, height: 80, hasAlpha: true)
        let destinationURL = scratchDir.appendingPathComponent("output.jpg")

        let options = ImageConversionOptions.forAction("png-to-jpeg")
        try await imageService.processImage(at: sourceURL, destinationURL: destinationURL, options: options)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        guard let destSource = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Could not open output JPEG with CGImageSource")
        }

        let typeIdentifier = CGImageSourceGetType(destSource) as String?
        XCTAssertEqual(typeIdentifier, "public.jpeg")

        guard let image = CGImageSourceCreateImageAtIndex(destSource, 0, nil) else {
            return XCTFail("Could not decode output JPEG")
        }
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 80)
    }

    func testJPEGToPNGConversion() async throws {
        let sourceURL = try createSyntheticImage(named: "photo.jpg", width: 80, height: 60, hasAlpha: false)
        let destinationURL = scratchDir.appendingPathComponent("photo.png")

        let options = ImageConversionOptions.forAction("jpeg-to-png")
        try await imageService.processImage(at: sourceURL, destinationURL: destinationURL, options: options)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        guard let destSource = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Could not open output PNG with CGImageSource")
        }

        let typeIdentifier = CGImageSourceGetType(destSource) as String?
        XCTAssertEqual(typeIdentifier, "public.png")

        guard let image = CGImageSourceCreateImageAtIndex(destSource, 0, nil) else {
            return XCTFail("Could not decode output PNG")
        }
        XCTAssertEqual(image.width, 80)
        XCTAssertEqual(image.height, 60)
    }

    func testResize50Percent() async throws {
        let sourceURL = try createSyntheticImage(named: "banner.png", width: 200, height: 120, hasAlpha: false)
        let destinationURL = scratchDir.appendingPathComponent("banner-resized.png")

        let options = ImageConversionOptions(targetUTType: .png, resizeScale: 0.5)
        try await imageService.processImage(at: sourceURL, destinationURL: destinationURL, options: options)

        guard let destSource = CGImageSourceCreateWithURL(destinationURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(destSource, 0, nil) else {
            return XCTFail("Could not inspect resized image")
        }

        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 60)
    }

    func testStripMetadata() async throws {
        let sourceURL = try createSyntheticImage(
            named: "tagged.png",
            width: 50,
            height: 50,
            exifComment: "SecretGPSLocation"
        )
        let destinationURL = scratchDir.appendingPathComponent("stripped.png")

        let options = ImageConversionOptions(targetUTType: .png, stripMetadata: true)
        try await imageService.processImage(at: sourceURL, destinationURL: destinationURL, options: options)

        guard let destSource = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Could not read stripped image")
        }

        let props = CGImageSourceCopyPropertiesAtIndex(destSource, 0, nil) as? [CFString: Any]
        let exif = props?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment], "EXIF comment should be stripped")
    }

    func testWebPConversionWithCWebP() async throws {
        let tools = ToolAvailability()
        guard case .available = tools.status(for: .cwebp) else {
            throw XCTSkip("cwebp is not available on this system")
        }

        let sourceURL = try createSyntheticImage(named: "graphic.png", width: 64, height: 64, hasAlpha: true)
        let destinationURL = scratchDir.appendingPathComponent("graphic.webp")

        let options = ImageConversionOptions(targetUTType: .webP, quality: 0.80)
        try await imageService.processImage(at: sourceURL, destinationURL: destinationURL, options: options)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        // Verify output file is a readable WebP image using native CGImageSource
        guard let destSource = CGImageSourceCreateWithURL(destinationURL as CFURL, nil) else {
            return XCTFail("Could not open converted WebP file")
        }

        guard let image = CGImageSourceCreateImageAtIndex(destSource, 0, nil) else {
            return XCTFail("Could not decode WebP image")
        }
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
    }

    // MARK: - End-to-End JobManager Execution

    @MainActor
    func testJobManagerExecutesRealImageJob() async throws {
        let sourceURL = try createSyntheticImage(named: "jobTest.png", width: 90, height: 70)
        let fileItem = FileItem(
            url: sourceURL,
            type: FileType(kind: .image, identifier: "public.png", localizedDescription: "PNG")
        )

        let outputFolder = scratchDir.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let jobManager = JobManager(imageService: imageService)
        jobManager.outputFolderProvider = { outputFolder }

        let action = ConversionAction(
            id: "png-to-jpeg",
            title: "PNG → JPEG",
            subtitle: "Test",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        )

        let job = jobManager.enqueue(action: action, inputFiles: [fileItem])

        // Await job completion
        for _ in 0..<50 {
            if job.status == .completed || job.status == .failed || job.status == .cancelled {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(job.status, .completed)
        XCTAssertEqual(job.outputURLs.count, 1)

        let generatedFile = try XCTUnwrap(job.outputURLs.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: generatedFile.path))
        XCTAssertEqual(generatedFile.pathExtension, "jpg")
    }
}
