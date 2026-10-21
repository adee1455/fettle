import Foundation

struct FileItem: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let url: URL
    let displayName: String
    let type: FileType
    let fileSize: Int64?
    let isDirectory: Bool

    init(id: UUID = UUID(), url: URL, displayName: String? = nil, type: FileType, fileSize: Int64? = nil, isDirectory: Bool = false) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.type = type
        self.fileSize = fileSize
        self.isDirectory = isDirectory
    }

    var fileSizeFormatted: String {
        guard let fileSize, fileSize >= 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
