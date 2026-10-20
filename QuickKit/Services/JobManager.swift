import AppKit
import Foundation

@MainActor
@Observable
final class JobManager {
    var jobs: [Job] = []
    var maxConcurrentJobs: Int = 4
    var outputFolderProvider: () -> URL = {
        OutputManager.resolvedOutputFolder(from: AppSettings())
    }

    let imageService: ImageService
    let pdfService: PDFService
    let mediaService: MediaService
    let documentService: DocumentService

    init(
        imageService: ImageService = ImageService(),
        pdfService: PDFService = PDFService(),
        mediaService: MediaService = MediaService(),
        documentService: DocumentService = DocumentService()
    ) {
        self.imageService = imageService
        self.pdfService = pdfService
        self.mediaService = mediaService
        self.documentService = documentService
    }

    func enqueue(action: ConversionAction, inputFiles: [FileItem]) -> Job {
        let job = Job(action: action, inputFiles: inputFiles)
        jobs.append(job)
        drainQueue()
        return job
    }

    func cancel(_ job: Job) {
        guard job.status == .queued || job.status == .running else { return }
        job.runTask?.cancel()
        job.runTask = nil
        job.status = .cancelled
        job.statusMessage = "Cancelled"
        drainQueue()
    }

    func clearFinished() {
        jobs.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    func removeJob(_ job: Job) {
        cancel(job)
        jobs.removeAll { $0.id == job.id }
    }

    // MARK: - Queue Drain

    func drainQueue() {
        let running = jobs.filter { $0.status == .running }.count
        let available = max(0, maxConcurrentJobs - running)
        let pending = jobs.filter { $0.status == .queued }.prefix(available)
        for job in pending {
            startJob(job)
        }
    }

    private func startJob(_ job: Job) {
        job.status = .running
        job.statusMessage = "Starting…"
        job.runTask = Task { @MainActor in
            if isImageAction(job.action.id) {
                await executeImageJob(job: job)
            } else if isPDFAction(job.action.id) {
                await executePDFJob(job: job)
            } else if isMediaAction(job.action.id) {
                await executeMediaJob(job: job)
            } else if isDocumentAction(job.action.id) {
                await executeDocumentJob(job: job)
            } else if isFileAction(job.action.id) {
                await executeFileActionJob(job: job)
            } else {
                await stubWorker(job: job)
            }
        }
    }

    // MARK: - Action Type Gating

    private func isImageAction(_ actionId: String) -> Bool {
        [
            "png-to-jpeg",
            "jpeg-to-png",
            "image-to-webp",
            "heic-to-jpeg",
            "resize-50",
            "strip-metadata"
        ].contains(actionId)
    }

    private func isPDFAction(_ actionId: String) -> Bool {
        ["merge-pdfs", "images-to-pdf", "split-pdf-pages"].contains(actionId)
    }

    private func isDocumentAction(_ actionId: String) -> Bool {
        ["document-to-pdf"].contains(actionId)
    }

    private func isMediaAction(_ actionId: String) -> Bool {
        [
            "video-to-mp4-h264",
            "video-to-mp4-hevc",
            "extract-audio-mp3",
            "extract-audio-aac",
            "extract-audio-wav",
            "video-to-gif",
            "video-thumbnail"
        ].contains(actionId)
    }

    private func isFileAction(_ actionId: String) -> Bool {
        ["reveal-in-finder", "copy-path", "duplicate-file"].contains(actionId)
    }

    // MARK: - Image Engine Execution

    private func executeImageJob(job: Job) async {
        let outputDirectory = outputFolderProvider()
        let options = ImageConversionOptions.forAction(job.action.id)
        let total = job.inputFiles.count
        var generatedURLs: [URL] = []

        for (index, fileItem) in job.inputFiles.enumerated() {
            guard !Task.isCancelled else {
                job.status = .cancelled
                job.statusMessage = "Cancelled"
                drainQueue()
                return
            }

            job.statusMessage = "Processing \(fileItem.displayName) (\(index + 1)/\(total))…"

            let targetExt: String
            switch job.action.id {
            case "png-to-jpeg", "heic-to-jpeg":
                targetExt = "jpg"
            case "jpeg-to-png":
                targetExt = "png"
            case "image-to-webp":
                targetExt = "webp"
            default:
                targetExt = fileItem.url.pathExtension.isEmpty ? "png" : fileItem.url.pathExtension
            }

            let destinationURL = OutputManager.destinationURL(
                for: fileItem.url,
                targetExtension: targetExt,
                in: outputDirectory
            )

            do {
                try await imageService.processImage(
                    at: fileItem.url,
                    destinationURL: destinationURL,
                    options: options
                )
                generatedURLs.append(destinationURL)
                job.outputURLs = generatedURLs
                job.progress = Double(index + 1) / Double(total)
            } catch {
                guard !Task.isCancelled else {
                    job.status = .cancelled
                    job.statusMessage = "Cancelled"
                    drainQueue()
                    return
                }
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.statusMessage = "Failed on \(fileItem.displayName)"
                drainQueue()
                return
            }
        }

        job.status = .completed
        job.progress = 1.0
        job.statusMessage = "Completed (\(generatedURLs.count) file\(generatedURLs.count == 1 ? "" : "s"))"
        job.completedAt = Date()
        drainQueue()
    }

    // MARK: - PDF Engine Execution

    private func executePDFJob(job: Job) async {
        let outputDirectory = outputFolderProvider()
        job.progress = 0.2

        do {
            switch job.action.id {
            case "merge-pdfs":
                guard !job.inputFiles.isEmpty else { return }
                job.statusMessage = "Merging \(job.inputFiles.count) PDF files…"
                let firstURL = job.inputFiles[0].url
                let baseName = "\(firstURL.deletingPathExtension().lastPathComponent) (Merged)"
                let destinationURL = OutputManager.nonCollidingURL(
                    for: baseName,
                    extension: "pdf",
                    in: outputDirectory
                )

                try pdfService.mergePDFs(sourceURLs: job.inputFiles.map(\.url), destinationURL: destinationURL)
                job.outputURLs = [destinationURL]
                job.statusMessage = "Merged into \(destinationURL.lastPathComponent)"

            case "images-to-pdf":
                guard !job.inputFiles.isEmpty else { return }
                job.statusMessage = "Creating PDF from \(job.inputFiles.count) image(s)…"
                let baseName = job.inputFiles.count == 1
                    ? job.inputFiles[0].url.deletingPathExtension().lastPathComponent
                    : "Combined Images"
                let destinationURL = OutputManager.nonCollidingURL(
                    for: baseName,
                    extension: "pdf",
                    in: outputDirectory
                )

                try pdfService.createPDF(fromImageURLs: job.inputFiles.map(\.url), destinationURL: destinationURL)
                job.outputURLs = [destinationURL]
                job.statusMessage = "Created \(destinationURL.lastPathComponent)"

            case "split-pdf-pages":
                guard let firstFile = job.inputFiles.first else { return }
                job.statusMessage = "Splitting \(firstFile.displayName)…"
                let generatedURLs = try pdfService.splitPages(
                    sourceURL: firstFile.url,
                    destinationDirectory: outputDirectory
                )
                job.outputURLs = generatedURLs
                job.statusMessage = "Extracted \(generatedURLs.count) page(s)"

            default:
                break
            }

            job.progress = 1.0
            job.status = .completed
            job.completedAt = Date()
        } catch {
            guard !Task.isCancelled else {
                job.status = .cancelled
                job.statusMessage = "Cancelled"
                drainQueue()
                return
            }
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.statusMessage = "PDF processing failed"
        }

        drainQueue()
    }

    // MARK: - Media Engine Execution

    private func executeMediaJob(job: Job) async {
        let outputDirectory = outputFolderProvider()
        let total = job.inputFiles.count
        var generatedURLs: [URL] = []

        for (index, fileItem) in job.inputFiles.enumerated() {
            guard !Task.isCancelled else {
                job.status = .cancelled
                job.statusMessage = "Cancelled"
                drainQueue()
                return
            }

            let targetExt: String
            switch job.action.id {
            case "video-to-mp4-h264", "video-to-mp4-hevc":
                targetExt = "mp4"
            case "extract-audio-mp3":
                targetExt = "mp3"
            case "extract-audio-aac":
                targetExt = "m4a"
            case "extract-audio-wav":
                targetExt = "wav"
            case "video-to-gif":
                targetExt = "gif"
            case "video-thumbnail":
                targetExt = "jpg"
            default:
                targetExt = "mp4"
            }

            let destinationURL = OutputManager.destinationURL(
                for: fileItem.url,
                targetExtension: targetExt,
                in: outputDirectory
            )

            job.statusMessage = "Processing \(fileItem.displayName) (\(index + 1)/\(total))…"

            do {
                try await mediaService.processMedia(
                    at: fileItem.url,
                    destinationURL: destinationURL,
                    actionId: job.action.id
                ) { [weak job] ratio, status in
                    Task { @MainActor in
                        guard let job else { return }
                        let overallProgress = (Double(index) + ratio) / Double(total)
                        job.progress = min(1.0, max(0.0, overallProgress))
                        job.statusMessage = "\(fileItem.displayName): \(status)"
                    }
                }

                guard !Task.isCancelled else {
                    job.status = .cancelled
                    job.statusMessage = "Cancelled"
                    drainQueue()
                    return
                }

                generatedURLs.append(destinationURL)
                job.outputURLs = generatedURLs
                job.progress = Double(index + 1) / Double(total)
            } catch {
                guard !Task.isCancelled else {
                    job.status = .cancelled
                    job.statusMessage = "Cancelled"
                    drainQueue()
                    return
                }
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.statusMessage = "Failed on \(fileItem.displayName): \(error.localizedDescription)"
                drainQueue()
                return
            }
        }

        job.status = .completed
        job.progress = 1.0
        job.statusMessage = "Completed (\(generatedURLs.count) file\(generatedURLs.count == 1 ? "" : "s"))"
        job.completedAt = Date()
        drainQueue()
    }

    // MARK: - Document Actions Execution

    private func executeDocumentJob(job: Job) async {
        let outDir = outputFolderProvider()
        var outputs: [URL] = []
        let total = Double(job.inputFiles.count)

        for (index, file) in job.inputFiles.enumerated() {
            guard !Task.isCancelled else {
                job.status = .cancelled
                job.statusMessage = "Cancelled"
                drainQueue()
                return
            }

            job.statusMessage = "Converting \(file.displayName) (\(index + 1)/\(Int(total)))…"
            let baseName = file.url.deletingPathExtension().lastPathComponent
            let dest = OutputManager.nonCollidingURL(for: baseName, extension: "pdf", in: outDir)

            do {
                try await documentService.convertToPDF(
                    sourceURL: file.url,
                    destinationURL: dest
                )
                outputs.append(dest)
                let overall = Double(index + 1) / total
                job.progress = overall
                job.statusMessage = "\(file.displayName) → PDF"
            } catch {
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.completedAt = Date()
                drainQueue()
                return
            }
        }

        job.outputURLs = outputs
        job.status = .completed
        job.progress = 1.0
        job.statusMessage = "Converted \(outputs.count) document(s) to PDF"
        job.completedAt = Date()
        drainQueue()
    }

    // MARK: - File Actions Execution

    private func executeFileActionJob(job: Job) async {
        switch job.action.id {
        case "reveal-in-finder":
            let urls = job.inputFiles.map(\.url)
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            job.status = .completed
            job.progress = 1.0
            job.statusMessage = "Revealed in Finder"
        case "copy-path":
            let paths = job.inputFiles.map(\.url.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
            job.status = .completed
            job.progress = 1.0
            job.statusMessage = "Path copied to clipboard"
        case "duplicate-file":
            var duplicates: [URL] = []
            for file in job.inputFiles {
                let dir = file.url.deletingLastPathComponent()
                let dest = OutputManager.nonCollidingURL(
                    for: "\(file.url.deletingPathExtension().lastPathComponent) copy",
                    extension: file.url.pathExtension,
                    in: dir
                )
                do {
                    try FileManager.default.copyItem(at: file.url, to: dest)
                    duplicates.append(dest)
                } catch {
                    job.status = .failed
                    job.errorMessage = error.localizedDescription
                    drainQueue()
                    return
                }
            }
            job.outputURLs = duplicates
            job.status = .completed
            job.progress = 1.0
            job.statusMessage = "Duplicated \(duplicates.count) file(s)"
        default:
            break
        }
        job.completedAt = Date()
        drainQueue()
    }

    // MARK: - Stub Worker (simulates progress for future milestones)

    private func stubWorker(job: Job) async {
        let steps = 10
        for step in 1...steps {
            guard !Task.isCancelled else {
                job.status = .cancelled
                job.statusMessage = "Cancelled"
                drainQueue()
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                job.status = .cancelled
                job.statusMessage = "Cancelled"
                drainQueue()
                return
            }
            job.progress = Double(step) / Double(steps)
            job.statusMessage = "Step \(step)/\(steps)…"
        }

        guard !Task.isCancelled else {
            job.status = .cancelled
            job.statusMessage = "Cancelled"
            drainQueue()
            return
        }

        job.status = .completed
        job.progress = 1.0
        job.statusMessage = "Completed"
        job.completedAt = Date()
        drainQueue()
    }
}
