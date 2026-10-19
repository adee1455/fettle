import AppKit
import Foundation
import PDFKit

enum PDFServiceError: LocalizedError, Equatable {
    case unreadableSource(URL)
    case passwordProtected(URL)
    case emptyDocument(URL)
    case pageExtractionFailed(pageIndex: Int, url: URL)
    case destinationWriteFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableSource(let url):
            "Could not open PDF file at \(url.lastPathComponent)"
        case .passwordProtected(let url):
            "The PDF file '\(url.lastPathComponent)' is password-protected and cannot be processed."
        case .emptyDocument(let url):
            "The PDF file '\(url.lastPathComponent)' contains no pages."
        case .pageExtractionFailed(let index, let url):
            "Failed to extract page \(index + 1) from \(url.lastPathComponent)"
        case .destinationWriteFailed(let url):
            "Failed to save PDF to \(url.lastPathComponent)"
        }
    }
}

final class PDFService: Sendable {
    /// Merge multiple PDF files sequentially into a single PDF document.
    func mergePDFs(sourceURLs: [URL], destinationURL: URL) throws {
        guard !sourceURLs.isEmpty else { return }

        let mergedDocument = PDFDocument()
        var totalPageIndex = 0

        for url in sourceURLs {
            guard let document = PDFDocument(url: url) else {
                throw PDFServiceError.unreadableSource(url)
            }
            if document.isLocked {
                throw PDFServiceError.passwordProtected(url)
            }
            let count = document.pageCount
            guard count > 0 else {
                throw PDFServiceError.emptyDocument(url)
            }

            for pageIndex in 0..<count {
                guard let page = document.page(at: pageIndex) else {
                    throw PDFServiceError.pageExtractionFailed(pageIndex: pageIndex, url: url)
                }
                mergedDocument.insert(page, at: totalPageIndex)
                totalPageIndex += 1
            }
        }

        try writeDocumentAtomically(mergedDocument, to: destinationURL)
    }

    /// Convert a list of image files into a single multi-page PDF document.
    func createPDF(fromImageURLs imageURLs: [URL], destinationURL: URL) throws {
        guard !imageURLs.isEmpty else { return }

        let pdfDocument = PDFDocument()

        for (index, imageURL) in imageURLs.enumerated() {
            guard let nsImage = NSImage(contentsOf: imageURL) else {
                throw PDFServiceError.unreadableSource(imageURL)
            }
            guard let page = PDFPage(image: nsImage) else {
                throw PDFServiceError.pageExtractionFailed(pageIndex: index, url: imageURL)
            }
            pdfDocument.insert(page, at: index)
        }

        try writeDocumentAtomically(pdfDocument, to: destinationURL)
    }

    /// Split a multi-page PDF into individual single-page PDF files.
    func splitPages(sourceURL: URL, destinationDirectory: URL) throws -> [URL] {
        guard let document = PDFDocument(url: sourceURL) else {
            throw PDFServiceError.unreadableSource(sourceURL)
        }
        if document.isLocked {
            throw PDFServiceError.passwordProtected(sourceURL)
        }
        let count = document.pageCount
        guard count > 0 else {
            throw PDFServiceError.emptyDocument(sourceURL)
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var generatedURLs: [URL] = []

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        for pageIndex in 0..<count {
            guard let page = document.page(at: pageIndex) else {
                throw PDFServiceError.pageExtractionFailed(pageIndex: pageIndex, url: sourceURL)
            }

            let singlePageDoc = PDFDocument()
            singlePageDoc.insert(page, at: 0)

            let candidateName = "\(baseName) (Page \(pageIndex + 1))"
            let pageURL = OutputManager.nonCollidingURL(
                for: candidateName,
                extension: "pdf",
                in: destinationDirectory
            )

            try writeDocumentAtomically(singlePageDoc, to: pageURL)
            generatedURLs.append(pageURL)
        }

        return generatedURLs
    }

    // MARK: - Safe Atomic Write

    private func writeDocumentAtomically(_ document: PDFDocument, to destinationURL: URL) throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickKitPDF-\(UUID().uuidString).pdf")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard document.write(to: tempURL) else {
            throw PDFServiceError.destinationWriteFailed(destinationURL)
        }

        // Verify written file is non-empty
        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        guard let size = attributes[.size] as? Int64, size > 0 else {
            throw PDFServiceError.destinationWriteFailed(destinationURL)
        }

        let destinationDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    }
}
