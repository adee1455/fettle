import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageServiceError: LocalizedError, Equatable {
    case unreadableSource(URL)
    case decodingFailed(URL)
    case destinationCreationFailed(URL)
    case encodingFailed(URL)
    case toolUnavailable(KnownTool)
    case invalidOptions(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource(let url):
            "Could not open image at \(url.lastPathComponent)"
        case .decodingFailed(let url):
            "Failed to decode image data from \(url.lastPathComponent)"
        case .destinationCreationFailed(let url):
            "Failed to create output file for \(url.lastPathComponent)"
        case .encodingFailed(let url):
            "Failed to write image data to \(url.lastPathComponent)"
        case .toolUnavailable(let tool):
            "Required tool \(tool.executableName) is not available"
        case .invalidOptions(let message):
            message
        }
    }
}

struct ImageConversionOptions: Sendable {
    var targetUTType: UTType              // .jpeg, .png, .webP, .heic
    var quality: Double = 0.85            // 0.0 ... 1.0 (for lossy formats)
    var resizeScale: Double? = nil        // e.g. 0.5 for 50%
    var maxDimension: CGFloat? = nil      // Bounding box constraint
    var stripMetadata: Bool = false       // Remove EXIF/GPS tags
    var flattenAlphaColor: CGColor? = nil // Default: white for JPEG

    static func forAction(_ actionId: String) -> ImageConversionOptions {
        switch actionId {
        case "png-to-jpeg":
            return ImageConversionOptions(
                targetUTType: .jpeg,
                quality: 0.85,
                flattenAlphaColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            )
        case "jpeg-to-png":
            return ImageConversionOptions(targetUTType: .png)
        case "image-to-webp":
            return ImageConversionOptions(targetUTType: .webP, quality: 0.80)
        case "heic-to-jpeg":
            return ImageConversionOptions(
                targetUTType: .jpeg,
                quality: 0.90,
                flattenAlphaColor: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            )
        case "resize-50":
            return ImageConversionOptions(targetUTType: .png, resizeScale: 0.5)
        case "strip-metadata":
            return ImageConversionOptions(targetUTType: .png, stripMetadata: true)
        default:
            return ImageConversionOptions(targetUTType: .png)
        }
    }
}

final class ImageService: Sendable {
    private let toolAvailability: ToolAvailability

    init(toolAvailability: ToolAvailability = ToolAvailability()) {
        self.toolAvailability = toolAvailability
    }

    /// Process an image file and write to the specified destination URL atomically.
    func processImage(
        at sourceURL: URL,
        destinationURL: URL,
        options: ImageConversionOptions
    ) async throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageServiceError.unreadableSource(sourceURL)
        }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: true]
        guard let originalImage = CGImageSourceCreateImageAtIndex(source, 0, sourceOptions as CFDictionary) else {
            throw ImageServiceError.decodingFailed(sourceURL)
        }

        let isWebP = options.targetUTType == .webP || options.targetUTType.identifier == "org.webmproject.webp"

        // Handle WebP encoding via cwebp fallback
        if isWebP {
            try await processWebP(
                originalImage: originalImage,
                source: source,
                destinationURL: destinationURL,
                options: options
            )
            return
        }

        // Native Image I/O processing (JPEG, PNG, HEIC, TIFF, etc.)
        try processNativeImageIO(
            originalImage: originalImage,
            source: source,
            destinationURL: destinationURL,
            options: options
        )
    }

    // MARK: - Native Image I/O Pipeline

    private func processNativeImageIO(
        originalImage: CGImage,
        source: CGImageSource,
        destinationURL: URL,
        options: ImageConversionOptions
    ) throws {
        let transformedImage = transformImage(originalImage: originalImage, options: options)

        // Write to temporary location first for atomicity
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fettle-\(UUID().uuidString)")
            .appendingPathExtension(destinationURL.pathExtension)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            options.targetUTType.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageServiceError.destinationCreationFailed(destinationURL)
        }

        var properties: [CFString: Any] = [:]

        if !options.stripMetadata {
            if let existingProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                properties = existingProps
            }
        }

        // Set lossy compression quality for JPEG / HEIC
        if options.targetUTType == .jpeg || options.targetUTType == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(destination, transformedImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageServiceError.encodingFailed(destinationURL)
        }

        // Verify temp file exists and has non-zero size
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        guard let size = attributes[.size] as? Int64, size > 0 else {
            throw ImageServiceError.encodingFailed(destinationURL)
        }

        // Ensure parent directory exists and move atomically
        let destinationDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    }

    // MARK: - WebP Pipeline via cwebp

    private func processWebP(
        originalImage: CGImage,
        source: CGImageSource,
        destinationURL: URL,
        options: ImageConversionOptions
    ) async throws {
        let status = toolAvailability.status(for: .cwebp)
        guard case .available(let cwebpURL, _) = status else {
            throw ImageServiceError.toolUnavailable(.cwebp)
        }

        let transformedImage = transformImage(originalImage: originalImage, options: options)

        // Write transformed image as intermediate PNG
        let tempPNG = FileManager.default.temporaryDirectory
            .appendingPathComponent("FettleWebPInput-\(UUID().uuidString).png")
        let tempWebP = FileManager.default.temporaryDirectory
            .appendingPathComponent("FettleWebPOutput-\(UUID().uuidString).webp")

        defer {
            try? FileManager.default.removeItem(at: tempPNG)
            try? FileManager.default.removeItem(at: tempWebP)
        }

        guard let pngDest = CGImageDestinationCreateWithURL(
            tempPNG as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageServiceError.destinationCreationFailed(tempPNG)
        }

        CGImageDestinationAddImage(pngDest, transformedImage, nil)
        guard CGImageDestinationFinalize(pngDest) else {
            throw ImageServiceError.encodingFailed(tempPNG)
        }

        // Execute cwebp: -q <0-100> <input> -o <output>
        let qualityInt = Int(clamping: Int(options.quality * 100))
        var args = ["-q", "\(qualityInt)", tempPNG.path, "-o", tempWebP.path]
        if options.stripMetadata {
            args.append(contentsOf: ["-metadata", "none"])
        }

        _ = try await ProcessRunner.run(executableURL: cwebpURL, arguments: args)

        guard FileManager.default.fileExists(atPath: tempWebP.path) else {
            throw ImageServiceError.encodingFailed(destinationURL)
        }

        // Ensure parent directory exists and move atomically
        let destinationDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempWebP, to: destinationURL)
    }

    // MARK: - Image Transformations (Resize & Alpha Flattening)

    private func transformImage(originalImage: CGImage, options: ImageConversionOptions) -> CGImage {
        let origWidth = CGFloat(originalImage.width)
        let origHeight = CGFloat(originalImage.height)

        var targetWidth = origWidth
        var targetHeight = origHeight

        // Apply scale
        if let scale = options.resizeScale, scale > 0 {
            targetWidth = max(1, round(origWidth * scale))
            targetHeight = max(1, round(origHeight * scale))
        }

        // Apply max dimension constraint
        if let maxDim = options.maxDimension, maxDim > 0 {
            let maxCurrent = max(targetWidth, targetHeight)
            if maxCurrent > maxDim {
                let factor = maxDim / maxCurrent
                targetWidth = max(1, round(targetWidth * factor))
                targetHeight = max(1, round(targetHeight * factor))
            }
        }

        let isResizing = (targetWidth != origWidth || targetHeight != origHeight)
        let isFlattening = options.flattenAlphaColor != nil || options.targetUTType == .jpeg

        // If no resize or flattening needed, return original
        if !isResizing && !isFlattening {
            return originalImage
        }

        let width = Int(targetWidth)
        let height = Int(targetHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = isFlattening
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return originalImage
        }

        // Fill background matte if flattening alpha
        if isFlattening {
            let matte = options.flattenAlphaColor ?? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            context.setFillColor(matte)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        context.interpolationQuality = .high
        context.draw(originalImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage() ?? originalImage
    }
}
