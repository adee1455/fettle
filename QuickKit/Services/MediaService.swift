import AVFoundation
import AppKit
import Foundation
import CoreGraphics
import ImageIO

enum MediaServiceError: LocalizedError, Equatable, Sendable {
    case toolUnavailable(tool: KnownTool, reason: String)
    case unsupportedAction(String)
    case unreadableMedia(String)
    case transcodeFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolUnavailable(let tool, let reason):
            "\(tool.executableName.uppercased()) required: \(reason) (\(tool.installHint))"
        case .unsupportedAction(let id):
            "Unsupported media action: \(id)"
        case .unreadableMedia(let msg):
            "Cannot read media file: \(msg)"
        case .transcodeFailed(let msg):
            "Transcoding failed: \(msg)"
        case .cancelled:
            "Media processing was cancelled"
        }
    }
}

struct FFmpegProgressSnapshot: Equatable, Sendable {
    var outTimeMicroseconds: Int64 = 0
    var outTimeString: String = ""
    var speed: Double = 0.0
    var isEnd: Bool = false

    func progressRatio(totalDurationSeconds: Double) -> Double {
        guard totalDurationSeconds > 0 else {
            return isEnd ? 1.0 : 0.0
        }
        let currentSeconds = Double(outTimeMicroseconds) / 1_000_000.0
        let ratio = currentSeconds / totalDurationSeconds
        return min(1.0, max(0.0, ratio))
    }
}

final class FFmpegProgressParser: @unchecked Sendable {
    private var current = FFmpegProgressSnapshot()
    private let lock = NSLock()

    init() {}

    func parse(line: String) -> FFmpegProgressSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalsIndex = trimmed.firstIndex(of: "=") else { return nil }

        let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

        switch key {
        case "out_time_us":
            if let microseconds = Int64(value) {
                current.outTimeMicroseconds = microseconds
            }
        case "out_time":
            current.outTimeString = value
        case "speed":
            let cleaned = value.replacingOccurrences(of: "x", with: "").trimmingCharacters(in: .whitespaces)
            if let spd = Double(cleaned) {
                current.speed = spd
            }
        case "progress":
            if value == "end" {
                current.isEnd = true
            }
            return current
        default:
            break
        }
        return nil
    }

    var latest: FFmpegProgressSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

struct FFmpegCommandBuilder: Sendable {
    static func arguments(
        for actionId: String,
        inputURL: URL,
        outputURL: URL
    ) -> [String] {
        var args: [String] = ["-y", "-hide_banner"]

        switch actionId {
        case "video-to-mp4-h264":
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "23",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "128k",
                "-movflags", "+faststart",
                outputURL.path
            ]

        case "video-to-mp4-hevc":
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                "-c:v", "libx265",
                "-crf", "28",
                "-c:a", "aac",
                "-b:a", "128k",
                "-tag:v", "hvc1",
                outputURL.path
            ]

        case "extract-audio-mp3":
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                "-vn",
                "-c:a", "libmp3lame",
                "-q:a", "2",
                outputURL.path
            ]

        case "extract-audio-aac":
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                "-vn",
                "-c:a", "aac",
                "-b:a", "192k",
                outputURL.path
            ]

        case "extract-audio-wav":
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                "-vn",
                "-c:a", "pcm_s16le",
                "-ar", "44100",
                outputURL.path
            ]

        case "video-to-gif":
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                "-filter_complex", "[0:v] fps=15,scale=480:-1:flags=lanczos,split [a][b];[a] palettegen [p];[b][p] paletteuse",
                outputURL.path
            ]

        case "video-thumbnail":
            args += [
                "-ss", "00:00:01",
                "-i", inputURL.path,
                "-vframes", "1",
                "-q:v", "2",
                outputURL.path
            ]

        default:
            args += [
                "-progress", "pipe:1",
                "-i", inputURL.path,
                outputURL.path
            ]
        }

        return args
    }
}

final class MediaService: Sendable {
    private let toolAvailability: ToolAvailability

    init(toolAvailability: ToolAvailability = ToolAvailability()) {
        self.toolAvailability = toolAvailability
    }

    func duration(for mediaURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: mediaURL)
        let cmTime = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(cmTime)
        guard seconds.isFinite && seconds > 0 else {
            return 0.0
        }
        return seconds
    }

    func processMedia(
        at sourceURL: URL,
        destinationURL: URL,
        actionId: String,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws {
        let ffmpegStatus = toolAvailability.status(for: .ffmpeg)

        if case .available(let ffmpegURL, _) = ffmpegStatus {
            try await processWithFFmpeg(
                ffmpegURL: ffmpegURL,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                actionId: actionId,
                onProgress: onProgress
            )
            return
        }

        // Native AVFoundation fallback when arm64 FFmpeg is missing/incompatible
        switch actionId {
        case "video-to-mp4-h264":
            try await exportWithAVFoundation(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                preset: AVAssetExportPresetHighestQuality,
                outputFileType: .mp4,
                onProgress: onProgress
            )
        case "extract-audio-aac":
            try await exportWithAVFoundation(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                preset: AVAssetExportPresetAppleM4A,
                outputFileType: .m4a,
                onProgress: onProgress
            )
        case "video-thumbnail":
            try await generateThumbnailWithAVFoundation(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
            onProgress?(1.0, "Thumbnail extracted")
        default:
            let reason: String
            if case .incompatibleArchitecture(_, let arch) = ffmpegStatus {
                reason = "Existing binary is \(arch.displayName) and cannot execute natively on this Mac."
            } else {
                reason = "Binary is not installed."
            }
            throw MediaServiceError.toolUnavailable(tool: .ffmpeg, reason: reason)
        }
    }

    // MARK: - FFmpeg Pipeline

    private func processWithFFmpeg(
        ffmpegURL: URL,
        sourceURL: URL,
        destinationURL: URL,
        actionId: String,
        onProgress: (@Sendable (Double, String) -> Void)?
    ) async throws {
        let totalDuration = (try? await duration(for: sourceURL)) ?? 0.0
        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(destinationURL.pathExtension)

        defer {
            try? FileManager.default.removeItem(at: tempDestination)
        }

        let args = FFmpegCommandBuilder.arguments(
            for: actionId,
            inputURL: sourceURL,
            outputURL: tempDestination
        )

        let parser = FFmpegProgressParser()

        do {
            _ = try await ProcessRunner.runStreaming(
                executableURL: ffmpegURL,
                arguments: args
            ) { line in
                if let snapshot = parser.parse(line: line) {
                    let ratio = snapshot.progressRatio(totalDurationSeconds: totalDuration)
                    let status: String
                    if snapshot.speed > 0 {
                        status = "Transcoding \(Int(ratio * 100))% (\(String(format: "%.1f", snapshot.speed))x)"
                    } else if !snapshot.outTimeString.isEmpty {
                        status = "Transcoding \(snapshot.outTimeString)…"
                    } else {
                        status = "Transcoding…"
                    }
                    onProgress?(ratio, status)
                }
            }

            guard FileManager.default.fileExists(atPath: tempDestination.path) else {
                throw MediaServiceError.transcodeFailed("FFmpeg did not generate the output file.")
            }

            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempDestination, to: destinationURL)
            onProgress?(1.0, "Completed")
        } catch {
            if Task.isCancelled {
                throw MediaServiceError.cancelled
            }
            throw error
        }
    }

    // MARK: - AVFoundation Fallback Pipeline

    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    private func exportWithAVFoundation(
        sourceURL: URL,
        destinationURL: URL,
        preset: String,
        outputFileType: AVFileType,
        onProgress: (@Sendable (Double, String) -> Void)?
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MediaServiceError.transcodeFailed("Failed to create AVAssetExportSession.")
        }

        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(destinationURL.pathExtension)

        defer {
            try? FileManager.default.removeItem(at: tempDestination)
        }

        exportSession.outputURL = tempDestination
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true

        let box = ExportSessionBox(exportSession)
        let progressTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                let progress = Double(box.session.progress)
                let pct = Int(progress * 100)
                onProgress?(progress, "Processing \(pct)%…")
            }
        }
        defer { progressTimer.cancel() }

        await exportSession.export()

        if Task.isCancelled {
            exportSession.cancelExport()
            throw MediaServiceError.cancelled
        }

        guard exportSession.status == .completed else {
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw MediaServiceError.transcodeFailed(errorMsg)
        }

        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempDestination, to: destinationURL)
        onProgress?(1.0, "Completed")
    }

    private func generateThumbnailWithAVFoundation(
        sourceURL: URL,
        destinationURL: URL
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)

        let durationSeconds = (try? await duration(for: sourceURL)) ?? 0.0
        let targetTimeSeconds = min(1.0, max(0.0, durationSeconds / 2.0))
        let time = CMTime(seconds: targetTimeSeconds, preferredTimescale: 600)

        let cgImage: CGImage
        do {
            let (image, _) = try await generator.image(at: time)
            cgImage = image
        } catch {
            throw MediaServiceError.transcodeFailed("Could not extract frame: \(error.localizedDescription)")
        }

        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw MediaServiceError.transcodeFailed("Could not initialize JPEG destination.")
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw MediaServiceError.transcodeFailed("Failed to finalize thumbnail.")
        }
    }
}
