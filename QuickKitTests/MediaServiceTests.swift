import AVFoundation
import XCTest
@testable import QuickKit

final class MediaServiceTests: XCTestCase {

    // MARK: - Progress Parser Tests

    func testFFmpegProgressParserParsesStandardOutput() {
        let parser = FFmpegProgressParser()

        let lines = [
            "frame=100",
            "fps=48.2",
            "stream_0_0_q=28.0",
            "bitrate= 512.4kbits/s",
            "total_size=1048576",
            "out_time_us=5000000",
            "out_time=00:00:05.000000",
            "dup_frames=0",
            "drop_frames=0",
            "speed=2.4x",
            "progress=continue"
        ]

        var lastSnapshot: FFmpegProgressSnapshot?
        for line in lines {
            if let snap = parser.parse(line: line) {
                lastSnapshot = snap
            }
        }

        XCTAssertNotNil(lastSnapshot)
        guard let snap = lastSnapshot else { return }

        XCTAssertEqual(snap.outTimeMicroseconds, 5_000_000)
        XCTAssertEqual(snap.outTimeString, "00:00:05.000000")
        XCTAssertEqual(snap.speed, 2.4, accuracy: 0.01)
        XCTAssertFalse(snap.isEnd)

        // 5 seconds out of 20 seconds total = 25% (0.25)
        let ratio = snap.progressRatio(totalDurationSeconds: 20.0)
        XCTAssertEqual(ratio, 0.25, accuracy: 0.001)

        // Feed progress=end
        let endSnap = parser.parse(line: "progress=end")
        XCTAssertNotNil(endSnap)
        XCTAssertTrue(endSnap?.isEnd == true)
        XCTAssertEqual(endSnap?.progressRatio(totalDurationSeconds: 20.0), 0.25)
    }

    func testFFmpegProgressParserHandlesMissingOrZeroDuration() {
        let parser = FFmpegProgressParser()
        _ = parser.parse(line: "out_time_us=2000000")
        _ = parser.parse(line: "progress=continue")

        let latest = parser.latest
        XCTAssertEqual(latest.progressRatio(totalDurationSeconds: 0.0), 0.0)

        _ = parser.parse(line: "progress=end")
        XCTAssertEqual(parser.latest.progressRatio(totalDurationSeconds: 0.0), 1.0)
    }

    // MARK: - Command Builder Tests

    func testCommandBuilderGeneratesExpectedArguments() {
        let input = URL(fileURLWithPath: "/tmp/sample.mov")
        let output = URL(fileURLWithPath: "/tmp/sample.mp4")

        let h264Args = FFmpegCommandBuilder.arguments(for: "video-to-mp4-h264", inputURL: input, outputURL: output)
        XCTAssertTrue(h264Args.contains("-progress"))
        XCTAssertTrue(h264Args.contains("pipe:1"))
        XCTAssertTrue(h264Args.contains("libx264"))
        XCTAssertTrue(h264Args.contains("yuv420p"))
        XCTAssertTrue(h264Args.contains("+faststart"))

        let hevcArgs = FFmpegCommandBuilder.arguments(for: "video-to-mp4-hevc", inputURL: input, outputURL: output)
        XCTAssertTrue(hevcArgs.contains("libx265"))
        XCTAssertTrue(hevcArgs.contains("hvc1"))

        let mp3Output = URL(fileURLWithPath: "/tmp/sample.mp3")
        let mp3Args = FFmpegCommandBuilder.arguments(for: "extract-audio-mp3", inputURL: input, outputURL: mp3Output)
        XCTAssertTrue(mp3Args.contains("-vn"))
        XCTAssertTrue(mp3Args.contains("libmp3lame"))

        let aacOutput = URL(fileURLWithPath: "/tmp/sample.m4a")
        let aacArgs = FFmpegCommandBuilder.arguments(for: "extract-audio-aac", inputURL: input, outputURL: aacOutput)
        XCTAssertTrue(aacArgs.contains("-vn"))
        XCTAssertTrue(aacArgs.contains("192k"))

        let wavOutput = URL(fileURLWithPath: "/tmp/sample.wav")
        let wavArgs = FFmpegCommandBuilder.arguments(for: "extract-audio-wav", inputURL: input, outputURL: wavOutput)
        XCTAssertTrue(wavArgs.contains("pcm_s16le"))

        let gifOutput = URL(fileURLWithPath: "/tmp/sample.gif")
        let gifArgs = FFmpegCommandBuilder.arguments(for: "video-to-gif", inputURL: input, outputURL: gifOutput)
        XCTAssertTrue(gifArgs.contains("-filter_complex"))
        XCTAssertTrue(gifArgs.contains { $0.contains("palettegen") })

        let thumbOutput = URL(fileURLWithPath: "/tmp/sample.jpg")
        let thumbArgs = FFmpegCommandBuilder.arguments(for: "video-thumbnail", inputURL: input, outputURL: thumbOutput)
        XCTAssertTrue(thumbArgs.contains("-vframes"))
    }

    // MARK: - ProcessRunner Streaming Tests

    func testProcessRunnerStreamingCapturesLines() async throws {
        final class LineCollector: @unchecked Sendable {
            var lines: [String] = []
            let lock = NSLock()
            func append(_ line: String) {
                lock.lock()
                defer { lock.unlock() }
                lines.append(line)
            }
        }

        let collector = LineCollector()
        let echoURL = URL(fileURLWithPath: "/bin/echo")

        let result = try await ProcessRunner.runStreaming(
            executableURL: echoURL,
            arguments: ["Hello QuickKit Media Engine"]
        ) { line in
            collector.append(line)
        }

        XCTAssertTrue(result.isSuccess)
        let captured = collector.lines
        XCTAssertTrue(captured.contains { $0.contains("Hello QuickKit Media Engine") })
    }

    // MARK: - Missing / Incompatible Tool Error Tests

    func testMissingToolThrowsDescriptiveError() async {
        let emptyAvailability = ToolAvailability(searchPaths: [])
        let service = MediaService(toolAvailability: emptyAvailability)

        let dummyInput = URL(fileURLWithPath: "/tmp/missing_tool_input.mp4")
        let dummyOutput = URL(fileURLWithPath: "/tmp/missing_tool_output.mp3")

        do {
            try await service.processMedia(
                at: dummyInput,
                destinationURL: dummyOutput,
                actionId: "extract-audio-mp3"
            )
            XCTFail("Expected missing tool error to be thrown")
        } catch let error as MediaServiceError {
            if case .toolUnavailable(let tool, let reason) = error {
                XCTAssertEqual(tool, .ffmpeg)
                XCTAssertTrue(reason.contains("not installed"))
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIncompatibleIntelToolThrowsArchitectureError() async {
        // On this Mac, ToolAvailability finds /usr/local/bin/ffmpeg as x86_64
        let tools = ToolAvailability()
        let status = tools.status(for: .ffmpeg)

        // Only assert if host indeed has an incompatible ffmpeg
        if case .incompatibleArchitecture = status {
            let service = MediaService(toolAvailability: tools)
            let dummyInput = URL(fileURLWithPath: "/tmp/test.mp4")
            let dummyOutput = URL(fileURLWithPath: "/tmp/test.mp3")

            do {
                try await service.processMedia(
                    at: dummyInput,
                    destinationURL: dummyOutput,
                    actionId: "extract-audio-mp3"
                )
                XCTFail("Expected architecture error to be thrown")
            } catch let error as MediaServiceError {
                if case .toolUnavailable(let tool, let reason) = error {
                    XCTAssertEqual(tool, .ffmpeg)
                    XCTAssertTrue(reason.contains("cannot execute natively"))
                } else {
                    XCTFail("Unexpected error: \(error)")
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - JobManager Media Integration Tests

    @MainActor
    func testJobManagerRejectsOrFailsOnUnavailableToolGracefully() async {
        let emptyAvailability = ToolAvailability(searchPaths: [])
        let mediaService = MediaService(toolAvailability: emptyAvailability)
        let jobManager = JobManager(mediaService: mediaService)

        let action = ConversionAction(
            id: "extract-audio-mp3",
            title: "Extract Audio → MP3",
            subtitle: "VBR",
            systemImage: "waveform",
            ringMode: .conversion,
            applicableKinds: [.video],
            requiredTool: .ffmpeg,
            minSelection: 1,
            maxSelection: nil
        )

        let inputURL = URL(fileURLWithPath: "/tmp/nonexistent.mp4")
        let item = FileItem(url: inputURL, type: FileType(kind: .video, identifier: "public.mpeg-4", localizedDescription: "MP4 Video"))

        let job = jobManager.enqueue(action: action, inputFiles: [item])

        // Wait for job to execute and fail gracefully
        for _ in 0..<20 {
            if job.status == .failed || job.status == .completed { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(job.status, .failed)
        XCTAssertNotNil(job.errorMessage)
        XCTAssertTrue(job.errorMessage?.contains("FFMPEG required") == true)
    }
}
