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

        // Cancellation handler: if task is cancelled, terminate process
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

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
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
