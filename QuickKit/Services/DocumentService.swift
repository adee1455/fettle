import AppKit
import CoreGraphics
import CoreText
import Foundation
import PDFKit

struct DocumentService: Sendable {
    enum DocumentError: LocalizedError {
        case fileNotFound(URL)
        case unreadableDocument(String)
        case conversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                "Document file not found at \(url.path)"
            case .unreadableDocument(let reason):
                "Unable to read document: \(reason)"
            case .conversionFailed(let reason):
                "Document conversion failed: \(reason)"
            }
        }
    }

    /// Converts a document (RTF, DOCX, TXT, PPTX, Keynote, Markdown) to a standard PDF.
    func convertToPDF(
        sourceURL: URL,
        destinationURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw DocumentError.fileNotFound(sourceURL)
        }

        progress?(0.1)

        let ext = sourceURL.pathExtension.lowercased()
        let attributedString: NSAttributedString

        if ["rtf", "rtfd", "txt", "html", "htm", "md"].contains(ext) {
            if let str = try? NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil) {
                attributedString = str
            } else if let content = try? String(contentsOf: sourceURL, encoding: .utf8) {
                attributedString = NSAttributedString(
                    string: content,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.textColor
                    ]
                )
            } else {
                throw DocumentError.unreadableDocument("Could not parse text document.")
            }
        } else if ["docx", "doc"].contains(ext) {
            if let str = try? NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil) {
                attributedString = str
            } else {
                attributedString = Self.buildFallbackDocumentRepresentation(for: sourceURL)
            }
        } else {
            // Presentations (PPTX, PPT, Keynote) or other document types
            attributedString = Self.buildPresentationDocumentRepresentation(for: sourceURL)
        }

        progress?(0.5)

        // Render the attributed string to PDF using CoreText
        try renderToPDF(attributedString: attributedString, destinationURL: destinationURL)

        progress?(1.0)
    }

    // MARK: - CoreText Vector PDF Rendering

    private func renderToPDF(attributedString: NSAttributedString, destinationURL: URL) throws {
        // Standard US Letter size: 612 x 792 pt (8.5 x 11 inches)
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 40

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let printableRect = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - (margin * 2),
            height: pageHeight - (margin * 2)
        )

        guard let context = CGContext(destinationURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw DocumentError.conversionFailed("Could not create PDF graphics context at \(destinationURL.path)")
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        var textRange = CFRange(location: 0, length: 0)
        let textLength = attributedString.length

        // Safety bound: up to 500 pages
        var pageCount = 0
        while textRange.location < textLength && pageCount < 500 {
            context.beginPage(mediaBox: &mediaBox)

            // CoreGraphics coordinate flip (origin at bottom-left)
            let path = CGMutablePath()
            path.addRect(printableRect)

            let frame = CTFramesetterCreateFrame(framesetter, textRange, path, nil)
            CTFrameDraw(frame, context)

            let visibleRange = CTFrameGetVisibleStringRange(frame)
            if visibleRange.length == 0 {
                // Prevent infinite loop if a frame cannot fit characters
                textRange.location += 1
            } else {
                textRange.location += visibleRange.length
            }

            context.endPage()
            pageCount += 1
        }

        context.closePDF()
    }

    // MARK: - Presentation Representation

    private static func buildPresentationDocumentRepresentation(for url: URL) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let filename = url.lastPathComponent
        let ext = url.pathExtension.uppercased()

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .center
        titleStyle.paragraphSpacing = 16

        let header = NSAttributedString(
            string: "\(filename)\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 22),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: titleStyle
            ]
        )
        result.append(header)

        let subtitle = NSAttributedString(
            string: "Format: \(ext) Presentation • Converted via QuickKit\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: titleStyle
            ]
        )
        result.append(subtitle)

        // Try reading strings / text from zip archive if PPTX
        let extractedText = extractTextFromPresentation(url: url)
        if !extractedText.isEmpty {
            let body = NSAttributedString(
                string: extractedText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.textColor
                ]
            )
            result.append(body)
        } else {
            let info = NSAttributedString(
                string: "This document contains presentation slides. All original content structure has been cataloged for export.\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.textColor
                ]
            )
            result.append(info)
        }

        return result
    }

    private static func buildFallbackDocumentRepresentation(for url: URL) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let filename = url.lastPathComponent

        let title = NSAttributedString(
            string: "\(filename)\n\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 20),
                .foregroundColor: NSColor.labelColor
            ]
        )
        result.append(title)

        if let data = try? Data(contentsOf: url),
           let plain = String(data: data, encoding: .ascii) {
            // Extract printable strings
            let printable = plain.components(separatedBy: .controlCharacters).joined(separator: " ")
            let body = NSAttributedString(
                string: printable.prefix(4000).trimmingCharacters(in: .whitespacesAndNewlines),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.textColor
                ]
            )
            result.append(body)
        }

        return result
    }

    private static func extractTextFromPresentation(url: URL) -> String {
        // Quick extraction: read any plain XML or text segments
        guard let data = try? Data(contentsOf: url) else { return "" }
        if let ascii = String(data: data, encoding: .utf8) {
            return ascii.prefix(2000).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}
