import Foundation
import UniformTypeIdentifiers

enum FileKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case image
    case audio
    case video
    case pdf
    case document
    case other
}

struct FileType: Equatable, Hashable, Sendable {
    var kind: FileKind
    var identifier: String
    var localizedDescription: String

    static func unknown(uti: String?) -> FileType {
        FileType(
            kind: .other,
            identifier: uti ?? "public.item",
            localizedDescription: "Unknown"
        )
    }
}

enum ActionRingMode: String, Equatable, Sendable, CaseIterable {
    case conversion
    case editing
    case fileActions

    var title: String {
        switch self {
        case .conversion: "Conversion"
        case .editing: "Editing"
        case .fileActions: "File actions"
        }
    }
}
