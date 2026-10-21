import Foundation

struct ActionRegistry: Sendable {
    /// The full catalogue of known actions.
    let actions: [ConversionAction]

    init(actions: [ConversionAction] = Self.buildCatalogue()) {
        self.actions = actions
    }

    /// Filter actions that apply to a given selection, ordered by smart relevance.
    func actions(
        for items: [FileItem],
        toolStatuses: [KnownTool: ToolStatus],
        ringMode: ActionRingMode? = nil
    ) -> [ConversionAction] {
        guard !items.isEmpty else { return [] }
        let kinds = Set(items.map(\.type.kind))
        let extensions = Set(items.map { $0.url.pathExtension.lowercased() })
        let count = items.count

        let filtered = actions.filter { action in
            // Ring mode filter
            if let ringMode, action.ringMode != ringMode { return false }

            // Kind filter: action must apply to ALL selected file kinds
            guard action.applicableKinds.isSuperset(of: kinds) else { return false }

            // Smart source extension filtering (e.g. PNG should not show JPEG->PNG)
            if let sourceExts = action.sourceExtensions {
                guard !extensions.isEmpty && extensions.isSubset(of: sourceExts) else { return false }
            }

            // Smart excluded extensions (e.g. WebP should not convert to WebP)
            if let excludedExts = action.excludedExtensions {
                guard !extensions.isSubset(of: excludedExts) else { return false }
            }

            // Cardinality
            guard count >= action.minSelection else { return false }
            if let max = action.maxSelection, count > max { return false }

            // Tool availability
            if let tool = action.requiredTool {
                guard toolStatuses[tool]?.isUsable == true else { return false }
            }

            return true
        }

        // Smart ordering:
        // 1. Suggested actions first
        // 2. Ascending by priority number
        return filtered.sorted { a, b in
            if a.isSuggested != b.isSuggested {
                return a.isSuggested && !b.isSuggested
            }
            return a.priority < b.priority
        }
    }

    static func buildCatalogue() -> [ConversionAction] {
        var list: [ConversionAction] = []

        // ==========================================
        // MARK: - Image Conversions (Smart Priority Order: WebP -> JPEG -> PDF -> PNG)
        // ==========================================

        // Image to WebP (Modern high-efficiency, default top recommendation for images)
        list.append(ConversionAction(
            id: "image-to-webp",
            title: "Convert to WebP",
            subtitle: "Modern Web format, Quality 80",
            systemImage: "photo.badge.arrow.down",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: ["webp"],
            isSuggested: true,
            priority: 10,
            targetFormat: "WEBP"
        ))

        // PNG -> JPEG
        list.append(ConversionAction(
            id: "png-to-jpeg",
            title: "Convert to JPEG",
            subtitle: "Smaller file size, Quality 85%",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: ["png"],
            excludedExtensions: nil,
            isSuggested: true,
            priority: 20,
            targetFormat: "JPEG"
        ))

        // JPEG -> PNG
        list.append(ConversionAction(
            id: "jpeg-to-png",
            title: "Convert to PNG",
            subtitle: "Lossless crisp image",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: ["jpg", "jpeg"],
            excludedExtensions: nil,
            isSuggested: true,
            priority: 20,
            targetFormat: "PNG"
        ))

        // HEIC -> JPEG
        list.append(ConversionAction(
            id: "heic-to-jpeg",
            title: "Convert to JPEG",
            subtitle: "Universal photo format, Quality 90%",
            systemImage: "photo",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: ["heic", "heif"],
            excludedExtensions: nil,
            isSuggested: true,
            priority: 20,
            targetFormat: "JPEG"
        ))

        // Images -> PDF
        list.append(ConversionAction(
            id: "images-to-pdf",
            title: "Convert to PDF",
            subtitle: "Single or multi-page PDF document",
            systemImage: "doc.richtext",
            ringMode: .conversion,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 30,
            targetFormat: "PDF"
        ))

        // ==========================================
        // MARK: - Document / Presentation Conversions (Smart suggestions)
        // ==========================================

        list.append(ConversionAction(
            id: "document-to-pdf",
            title: "Convert to PDF",
            subtitle: "Standardized document format",
            systemImage: "doc.richtext",
            ringMode: .conversion,
            applicableKinds: [.document],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: ["pdf"],
            isSuggested: true,
            priority: 10,
            targetFormat: "PDF"
        ))

        // ==========================================
        // MARK: - Media Conversions
        // ==========================================

        list.append(ConversionAction(
            id: "video-to-mp4-h264",
            title: "Video → MP4 (H.264)",
            subtitle: "Universal playback compatibility",
            systemImage: "film",
            ringMode: .conversion,
            applicableKinds: [.video],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 10,
            targetFormat: "MP4"
        ))

        list.append(ConversionAction(
            id: "video-to-mp4-hevc",
            title: "Video → MP4 (HEVC)",
            subtitle: "High efficiency compression",
            systemImage: "film.stack",
            ringMode: .conversion,
            applicableKinds: [.video],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: false,
            priority: 15,
            targetFormat: "HEVC"
        ))

        list.append(ConversionAction(
            id: "extract-audio-aac",
            title: "Extract Audio → AAC",
            subtitle: "Clean 192 kbps M4A / AAC audio",
            systemImage: "waveform.badge.plus",
            ringMode: .conversion,
            applicableKinds: [.video, .audio],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 20,
            targetFormat: "AAC"
        ))

        list.append(ConversionAction(
            id: "extract-audio-mp3",
            title: "Extract Audio → MP3",
            subtitle: "Universal VBR ~190 kbps audio",
            systemImage: "waveform",
            ringMode: .conversion,
            applicableKinds: [.video, .audio],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 25,
            targetFormat: "MP3"
        ))

        list.append(ConversionAction(
            id: "video-to-gif",
            title: "Video → Animated GIF",
            subtitle: "Optimized 480px, 15 fps clip",
            systemImage: "play.rectangle.on.rectangle",
            ringMode: .conversion,
            applicableKinds: [.video],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 30,
            targetFormat: "GIF"
        ))

        list.append(ConversionAction(
            id: "extract-audio-wav",
            title: "Extract Audio → WAV",
            subtitle: "Lossless 44.1 kHz PCM audio",
            systemImage: "waveform.circle",
            ringMode: .conversion,
            applicableKinds: [.video, .audio],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: false,
            priority: 40,
            targetFormat: "WAV"
        ))

        // ==========================================
        // MARK: - PDF Conversions
        // ==========================================

        list.append(ConversionAction(
            id: "merge-pdfs",
            title: "Merge PDFs",
            subtitle: "Combine into a single document",
            systemImage: "doc.on.doc",
            ringMode: .conversion,
            applicableKinds: [.pdf],
            requiredTool: nil,
            minSelection: 2,
            maxSelection: nil,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 10,
            targetFormat: "PDF"
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
            maxSelection: 1,
            sourceExtensions: nil,
            excludedExtensions: nil,
            isSuggested: true,
            priority: 10,
            targetFormat: "PDF"
        ))

        // ==========================================
        // MARK: - Editing Actions
        // ==========================================

        list.append(ConversionAction(
            id: "resize-50",
            title: "Resize 50%",
            subtitle: "Scale dimensions by half",
            systemImage: "arrow.down.right.and.arrow.up.left",
            ringMode: .editing,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            isSuggested: false,
            priority: 50,
            targetFormat: nil
        ))

        list.append(ConversionAction(
            id: "strip-metadata",
            title: "Strip Metadata",
            subtitle: "Remove EXIF, GPS and privacy data",
            systemImage: "eye.slash",
            ringMode: .editing,
            applicableKinds: [.image],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            isSuggested: false,
            priority: 60,
            targetFormat: nil
        ))

        list.append(ConversionAction(
            id: "video-thumbnail",
            title: "Extract Thumbnail",
            subtitle: "High-resolution snapshot as JPEG",
            systemImage: "camera.viewfinder",
            ringMode: .editing,
            applicableKinds: [.video],
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            isSuggested: false,
            priority: 70,
            targetFormat: "JPEG"
        ))

        // ==========================================
        // MARK: - File Actions
        // ==========================================

        list.append(ConversionAction(
            id: "reveal-in-finder",
            title: "Reveal in Finder",
            subtitle: "Show item in folder",
            systemImage: "folder",
            ringMode: .fileActions,
            applicableKinds: Set(FileKind.allCases),
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            isSuggested: false,
            priority: 100,
            targetFormat: nil
        ))

        list.append(ConversionAction(
            id: "copy-path",
            title: "Copy Path",
            subtitle: "Copy POSIX path to clipboard",
            systemImage: "doc.on.clipboard",
            ringMode: .fileActions,
            applicableKinds: Set(FileKind.allCases),
            requiredTool: nil,
            minSelection: 1,
            maxSelection: nil,
            isSuggested: false,
            priority: 110,
            targetFormat: nil
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
            maxSelection: nil,
            isSuggested: false,
            priority: 120,
            targetFormat: nil
        ))

        return list
    }
}
