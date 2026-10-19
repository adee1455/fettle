import Foundation

struct ActionRegistry: Sendable {
    /// The full catalogue of known actions.
    let actions: [ConversionAction]

    init(actions: [ConversionAction] = Self.buildCatalogue()) {
        self.actions = actions
    }

    /// Filter actions that apply to a given selection.
    func actions(
        for items: [FileItem],
        toolStatuses: [KnownTool: ToolStatus],
        ringMode: ActionRingMode? = nil
    ) -> [ConversionAction] {
        guard !items.isEmpty else { return [] }
        let kinds = Set(items.map(\.type.kind))
        let count = items.count
        return actions.filter { action in
            // Ring mode filter
            if let ringMode, action.ringMode != ringMode { return false }
            // Kind filter: action must apply to ALL selected file kinds
            guard action.applicableKinds.isSuperset(of: kinds) else { return false }
            // Cardinality
            guard count >= action.minSelection else { return false }
            if let max = action.maxSelection, count > max { return false }
            // Tool availability
            if let tool = action.requiredTool {
                guard toolStatuses[tool]?.isUsable == true else { return false }
            }
            return true
        }
    }

    static func buildCatalogue() -> [ConversionAction] {
        var list: [ConversionAction] = []

        // -- Conversion actions --
        // Image conversions (Image I/O, no external tool)
        list.append(ConversionAction(
            id: "png-to-jpeg",
            title: "PNG → JPEG",
            subtitle: "Lossy, Quality 85%",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "jpeg-to-png",
            title: "JPEG → PNG",
            subtitle: "Lossless",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "image-to-webp",
            title: "Image → WebP",
            subtitle: "Quality 80",
            systemImage: "photo.badge.arrow.down",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "heic-to-jpeg",
            title: "HEIC → JPEG",
            subtitle: "Quality 90%",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))

        // Media conversions (require ffmpeg)
        list.append(ConversionAction(
            id: "video-to-mp4-h264",
            title: "Video → MP4 (H.264)",
            subtitle: "CRF 23, AAC 128k",
            systemImage: "film",
            ringMode: .conversion,
            applicableKinds: [.video],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "extract-audio-mp3",
            title: "Extract Audio → MP3",
            subtitle: "VBR ~190 kbps",
            systemImage: "waveform",
            ringMode: .conversion,
            applicableKinds: [.video, .audio],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil
        ))

        // PDF actions (PDFKit, no external tool)
        list.append(ConversionAction(
            id: "merge-pdfs",
            title: "Merge PDFs",
            subtitle: "Combine into single document",
            systemImage: "doc.on.doc",
            ringMode: .conversion,
            applicableKinds: [.pdf],
            requiredTool: nil,
            minSelection: 2,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "split-pdf-pages",
            title: "Split PDF Pages",
            subtitle: "Export each page as a single-page PDF",
            systemImage: "doc.badge.plus",
            ringMode: .conversion,
            applicableKinds: [.pdf],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: 1
        ))
        list.append(ConversionAction(
            id: "images-to-pdf",
            title: "Images → PDF",
            subtitle: "Combine images into a multi-page PDF",
            systemImage: "doc.richtext",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))

        // -- Editing actions --
        list.append(ConversionAction(
            id: "resize-50",
            title: "Resize 50%",
            subtitle: "Scale to half dimensions",
            systemImage: "arrow.down.right.and.arrow.up.left",
            ringMode: .editing,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "strip-metadata",
            title: "Strip Metadata",
            subtitle: "Remove EXIF / GPS",
            systemImage: "eye.slash",
            ringMode: .editing,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))

        // -- File actions --
        list.append(ConversionAction(
            id: "reveal-in-finder",
            title: "Reveal in Finder",
            subtitle: "",
            systemImage: "folder",
            ringMode: .fileActions,
            applicableKinds: Set(FileKind.allCases),
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "copy-path",
            title: "Copy Path",
            subtitle: "POSIX path to clipboard",
            systemImage: "doc.on.clipboard",
            ringMode: .fileActions,
            applicableKinds: Set(FileKind.allCases),
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))
        list.append(ConversionAction(
            id: "duplicate-file",
            title: "Duplicate",
            subtitle: "Create a copy alongside original",
            systemImage: "plus.square.on.square",
            ringMode: .fileActions,
            applicableKinds: Set(FileKind.allCases),
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil
        ))

        return list
    }
}
