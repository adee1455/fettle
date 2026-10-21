import AppKit
import XCTest
@testable import Fettle

final class ToolAvailabilityTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FettleTools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let scratch {
            try? FileManager.default.removeItem(at: scratch)
        }
    }

    func testMissingTool() {
        let availability = ToolAvailability(searchPaths: [scratch])
        XCTAssertEqual(availability.status(for: .qpdf), .missing)
    }

    func testArm64BinaryIsAvailableOnThisHost() throws {
        #if !arch(arm64)
        throw XCTSkip("Host is not arm64")
        #endif
        let url = try writeThinMachO(named: "ffmpeg", cpuType: 0x0100_000c)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let availability = ToolAvailability(searchPaths: [scratch], hostArchitectureIsArm64: true)
        let status = availability.status(for: .ffmpeg) { FileManager.default.fileExists(atPath: $0.path) }
        guard case .available(_, let architecture) = status else {
            return XCTFail("Expected available, got \(status)")
        }
        XCTAssertEqual(architecture, .arm64)
    }

    func testX86_64BinaryIsIncompatibleOnArm64() throws {
        #if !arch(arm64)
        throw XCTSkip("Host is not arm64")
        #endif
        let url = try writeThinMachO(named: "ffmpeg", cpuType: 0x0100_0007)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let availability = ToolAvailability(searchPaths: [scratch], hostArchitectureIsArm64: true)
        let status = availability.status(for: .ffmpeg) { FileManager.default.fileExists(atPath: $0.path) }
        guard case .incompatibleArchitecture(_, let architecture) = status else {
            return XCTFail("Expected incompatible architecture, got \(status)")
        }
        XCTAssertEqual(architecture, .x86_64)
    }

    func testPrefersNativeWhenBothExist() throws {
        #if !arch(arm64)
        throw XCTSkip("Host is not arm64")
        #endif
        let intelDir = scratch.appendingPathComponent("intel")
        let armDir = scratch.appendingPathComponent("arm")
        try FileManager.default.createDirectory(at: intelDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: armDir, withIntermediateDirectories: true)
        let intel = try writeThinMachO(named: "ffmpeg", cpuType: 0x0100_0007, directory: intelDir)
        let arm = try writeThinMachO(named: "ffmpeg", cpuType: 0x0100_000c, directory: armDir)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: intel.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: arm.path)
        let availability = ToolAvailability(searchPaths: [intelDir, armDir])
        let status = availability.status(for: .ffmpeg) { FileManager.default.fileExists(atPath: $0.path) }
        guard case .available(let url, let architecture) = status else {
            return XCTFail("Expected available, got \(status)")
        }
        XCTAssertEqual(architecture, .arm64)
        XCTAssertEqual(url, arm)
    }

    func testRealIntelFFmpegIfPresent() throws {
        let ffmpeg = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        guard FileManager.default.fileExists(atPath: ffmpeg.path) else {
            throw XCTSkip("No /usr/local/bin/ffmpeg on this machine")
        }
        let architectures = try MachOReader.architectures(at: ffmpeg)
        if architectures.contains(.x86_64) && !architectures.contains(.arm64) {
            let availability = ToolAvailability(searchPaths: [ffmpeg.deletingLastPathComponent()])
            let status = availability.status(for: .ffmpeg)
            guard case .incompatibleArchitecture = status else {
                return XCTFail("Intel-only ffmpeg should be incompatible on arm64, got \(status)")
            }
        }
    }

    private func writeThinMachO(named: String, cpuType: UInt32, directory: URL? = nil) throws -> URL {
        let url = (directory ?? scratch).appendingPathComponent(named)
        var magic = UInt32(0xfeed_facf).littleEndian
        var cpu = cpuType.littleEndian
        var data = Data()
        data.append(Data(bytes: &magic, count: 4))
        data.append(Data(bytes: &cpu, count: 4))
        data.append(Data(count: 24))
        try data.write(to: url)
        return url
    }
}

final class MachOReaderTests: XCTestCase {
    func testReadsSystemARMBinary() throws {
        #if !arch(arm64)
        throw XCTSkip("Host is not arm64")
        #endif
        let url = URL(fileURLWithPath: "/usr/bin/true")
        let architectures = try MachOReader.architectures(at: url)
        XCTAssertTrue(architectures.contains(.arm64), "\(architectures)")
    }
}

final class DragPasteboardHelperTests: XCTestCase {
    @MainActor
    func testEmptyDragPasteboardFileTypeCheckDoesNotThrow() {
        let pasteboard = NSPasteboard(name: .drag)
        _ = DragInteractionMonitor.pasteboardHasFileURLType(pasteboard)
        _ = DragInteractionMonitor.readFileURLs(from: pasteboard)
    }
}
