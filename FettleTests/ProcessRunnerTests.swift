import XCTest
@testable import Fettle

final class ProcessRunnerTests: XCTestCase {
    func testEchoExecution() async throws {
        let echoURL = URL(fileURLWithPath: "/bin/echo")
        let result = try await ProcessRunner.run(executableURL: echoURL, arguments: ["Hello", "Fettle"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.utf8Output.trimmingCharacters(in: .whitespacesAndNewlines), "Hello Fettle")
    }

    func testNonExistentBinaryThrows() async {
        let badURL = URL(fileURLWithPath: "/nonexistent/binary/\(UUID().uuidString)")
        do {
            _ = try await ProcessRunner.run(executableURL: badURL, arguments: [])
            XCTFail("Expected ProcessRunnerError.executableNotFound")
        } catch let error as ProcessRunnerError {
            if case .executableNotFound = error {
                // Success
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFailingCommandThrowsExecutionFailed() async {
        let falseURL = URL(fileURLWithPath: "/usr/bin/false")
        do {
            _ = try await ProcessRunner.run(executableURL: falseURL, arguments: [])
            XCTFail("Expected ProcessRunnerError.executionFailed")
        } catch let error as ProcessRunnerError {
            if case .executionFailed(let code, _) = error {
                XCTAssertNotEqual(code, 0)
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
