import Foundation
import MachO

enum ExecutableArchitecture: Equatable, Sendable {
    case arm64
    case x86_64
    case unknown(cpuType: Int32)

    var displayName: String {
        switch self {
        case .arm64: "arm64"
        case .x86_64: "x86_64"
        case .unknown(let cpuType): "unknown(\(cpuType))"
        }
    }

    var isNativeOnThisMac: Bool {
        #if arch(arm64)
        if case .arm64 = self { return true }
        return false
        #elseif arch(x86_64)
        if case .x86_64 = self { return true }
        return false
        #else
        return false
        #endif
    }

    static func from(cpuType: Int32) -> ExecutableArchitecture {
        switch cpuType {
        case Int32(CPU_TYPE_ARM64): .arm64
        case Int32(CPU_TYPE_X86_64): .x86_64
        default: .unknown(cpuType: cpuType)
        }
    }
}

enum MachOReaderError: Error, Equatable {
    case unreadable
    case notMachO
}

enum MachOReader {
    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatCigam: UInt32 = 0xbebafeca
    private static let mhMagic64: UInt32 = 0xfeed_facf
    private static let mhCigam64: UInt32 = 0xcffa_edfe
    private static let mhMagic: UInt32 = 0xfeed_face
    private static let mhCigam: UInt32 = 0xcefa_edfe

    static func architectures(at url: URL) throws -> [ExecutableArchitecture] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 32)
        guard header.count >= 8 else { throw MachOReaderError.unreadable }

        let magic = header.uInt32(at: 0)
        switch magic {
        case mhMagic64:
            let cpu = Int32(bitPattern: header.uInt32(at: 4))
            return [ExecutableArchitecture.from(cpuType: cpu)]
        case mhCigam64:
            let cpu = Int32(bitPattern: header.uInt32(at: 4).byteSwapped)
            return [ExecutableArchitecture.from(cpuType: cpu)]
        case mhMagic:
            let cpu = Int32(bitPattern: header.uInt32(at: 4))
            return [ExecutableArchitecture.from(cpuType: cpu)]
        case mhCigam:
            let cpu = Int32(bitPattern: header.uInt32(at: 4).byteSwapped)
            return [ExecutableArchitecture.from(cpuType: cpu)]
        case fatMagic, fatCigam:
            return try fatArchitectures(handle: handle, swap: magic == fatCigam)
        default:
            throw MachOReaderError.notMachO
        }
    }

    private static func fatArchitectures(handle: FileHandle, swap: Bool) throws -> [ExecutableArchitecture] {
        try handle.seek(toOffset: 0)
        let prefix = handle.readData(ofLength: 8)
        guard prefix.count == 8 else { throw MachOReaderError.unreadable }
        var nfat = prefix.uInt32(at: 4)
        if swap { nfat = nfat.byteSwapped }
        let count = Int(min(nfat, 16))
        let sliceSize = 20
        let body = handle.readData(ofLength: count * sliceSize)
        guard body.count >= count * sliceSize else { throw MachOReaderError.unreadable }

        var result: [ExecutableArchitecture] = []
        for index in 0..<count {
            var cpu = body.uInt32(at: index * sliceSize)
            if swap { cpu = cpu.byteSwapped }
            result.append(ExecutableArchitecture.from(cpuType: Int32(bitPattern: cpu)))
        }
        return result
    }
}

private extension Data {
    func uInt32(at offset: Int) -> UInt32 {
        precondition(offset + 4 <= count)
        return self[offset..<offset + 4].withUnsafeBytes { pointer in
            pointer.loadUnaligned(as: UInt32.self)
        }
    }
}
