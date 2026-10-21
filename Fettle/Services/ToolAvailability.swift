import Foundation

enum KnownTool: String, CaseIterable, Sendable {
    case ffmpeg
    case ffprobe
    case magick
    case qpdf
    case cwebp
    case dwebp

    var executableName: String { rawValue }

    var installHint: String {
        switch self {
        case .ffmpeg, .ffprobe:
            "brew install ffmpeg"
        case .magick:
            "brew install imagemagick"
        case .qpdf:
            "brew install qpdf"
        case .cwebp, .dwebp:
            "brew install webp"
        }
    }
}

enum ToolStatus: Equatable, Sendable {
    case available(url: URL, architecture: ExecutableArchitecture)
    case missing
    case incompatibleArchitecture(url: URL, architecture: ExecutableArchitecture)

    var isUsable: Bool {
        if case .available = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .available(let url, let architecture):
            "Available (\(architecture.displayName)) at \(url.path)"
        case .missing:
            "Not found"
        case .incompatibleArchitecture(let url, let architecture):
            "Found \(architecture.displayName) binary at \(url.path), which cannot run on this Mac"
        }
    }
}

struct ToolAvailability: Sendable {
    var searchPaths: [URL]
    var hostArchitectureIsArm64: Bool

    init(
        searchPaths: [URL] = ToolAvailability.defaultSearchPaths,
        hostArchitectureIsArm64: Bool = {
            #if arch(arm64)
            true
            #else
            false
            #endif
        }()
    ) {
        self.searchPaths = searchPaths
        self.hostArchitectureIsArm64 = hostArchitectureIsArm64
    }

    static var defaultSearchPaths: [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: "/usr/bin"),
        ]
    }

    func status(for tool: KnownTool, fileExists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }) -> ToolStatus {
        status(executableName: tool.executableName, fileExists: fileExists)
    }

    func status(executableName: String, fileExists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }) -> ToolStatus {
        var firstHit: (URL, ExecutableArchitecture)?
        for directory in searchPaths {
            let candidate = directory.appendingPathComponent(executableName)
            guard fileExists(candidate) else { continue }
            let architectures: [ExecutableArchitecture]
            do {
                architectures = try MachOReader.architectures(at: candidate)
            } catch {
                architectures = [.unknown(cpuType: 0)]
            }
            if let native = architectures.first(where: \.isNativeOnThisMac) {
                return .available(url: candidate, architecture: native)
            }
            if firstHit == nil, let architecture = architectures.first {
                firstHit = (candidate, architecture)
            }
        }
        if let firstHit {
            return .incompatibleArchitecture(url: firstHit.0, architecture: firstHit.1)
        }
        return .missing
    }

    func snapshot() -> [KnownTool: ToolStatus] {
        var result: [KnownTool: ToolStatus] = [:]
        for tool in KnownTool.allCases {
            result[tool] = status(for: tool)
        }
        return result
    }
}
