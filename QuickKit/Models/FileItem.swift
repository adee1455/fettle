import Foundation

struct FileItem: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let url: URL
    let displayName: String
    let type: FileType

    init(id: UUID = UUID(), url: URL, displayName: String? = nil, type: FileType) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.type = type
    }
}
