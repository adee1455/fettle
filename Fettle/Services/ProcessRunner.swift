import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data

    var isSuccess: Bool { exitCode == 0 }
    var utf8Error: String { String(data: standardError, encoding: .utf8) ?? "" }
    var utf8Output: String { String(data: standardOutput, encoding: .utf8) ?? "" }
}

enum ProcessRunnerError: LocalizedError, Equatable {
    case executableNotFound(URL)
    case executionFailed(exitCode: Int32, message: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let url):
            "Executable not found at \(url.path)"
        case .executionFailed(let code, let msg):
            "Process failed with exit code \(code): \(msg)"
        case .cancelled:
            "Process execution was cancelled"
        }
    }
}

final class ProcessRunner: Sendable {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) async throws -> ProcessResult {
        try await runStreaming(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            onOutputLine: nil
        )
    }

    static func runStreaming(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        onOutputLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ProcessRunnerError.executableNotFound(executableURL)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if let onOutputLine {
                    let streamQueue = DispatchQueue(label: "com.itsadee.fettle.process.stream", qos: .userInitiated)
                    var stdoutAccumulator = Data()
                    var stderrAccumulator = Data()
                    var lineBuffer = ""

                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        streamQueue.async {
                            stdoutAccumulator.append(data)
                            if let text = String(data: data, encoding: .utf8) {
                                lineBuffer.append(text)
                                while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                                    let line = String(lineBuffer[..<newlineIndex])
                                    lineBuffer.removeSubrange(...newlineIndex)
                                    onOutputLine(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                                }
                            }
                        }
                    }

                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }
                        streamQueue.async {
                            stderrAccumulator.append(data)
                        }
                    }

                    DispatchQueue.global(qos: .userInitiated).async {
                        process.waitUntilExit()

                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil

                        streamQueue.sync {
                            if !lineBuffer.isEmpty {
                                let trimmed = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    onOutputLine(trimmed)
                                }
                                lineBuffer.removeAll()
                            }

                            let result = ProcessResult(
                                exitCode: process.terminationStatus,
                                standardOutput: stdoutAccumulator,
                                standardError: stderrAccumulator
                            )

                            if result.isSuccess {
                                continuation.resume(returning: result)
                            } else {
                                continuation.resume(
                                    throwing: ProcessRunnerError.executionFailed(
                                        exitCode: result.exitCode,
                                        message: result.utf8Error.trimmingCharacters(in: .whitespacesAndNewlines)
                                    )
                                )
                            }
                        }
                    }
                } else {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()

                        let result = ProcessResult(
                            exitCode: process.terminationStatus,
                            standardOutput: stdoutData,
                            standardError: stderrData
                        )

                        if result.isSuccess {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(
                                throwing: ProcessRunnerError.executionFailed(
                                    exitCode: result.exitCode,
                                    message: result.utf8Error.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                            )
                        }
                    }
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
