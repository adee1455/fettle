import Foundation
import UniformTypeIdentifiers

struct FileTypeDetector: Sendable {
    func detect(url: URL) -> FileType {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        let utType = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        return classify(utType: utType, fallbackUTI: utType?.identifier)
    }

    func classify(utType: UTType?, fallbackUTI: String?) -> FileType {
        guard let utType else {
            return .unknown(uti: fallbackUTI)
        }

        if utType.conforms(to: .pdf) {
            return FileType(kind: .pdf, identifier: utType.identifier, localizedDescription: utType.localizedDescription ?? "PDF")
        }
        if utType.conforms(to: .image) {
            return FileType(kind: .image, identifier: utType.identifier, localizedDescription: utType.localizedDescription ?? "Image")
        }
        if utType.conforms(to: .audiovisualContent) && utType.conforms(to: .audio) && !utType.conforms(to: .movie) {
            return FileType(kind: .audio, identifier: utType.identifier, localizedDescription: utType.localizedDescription ?? "Audio")
        }
        if utType.conforms(to: .movie) || utType.conforms(to: .audiovisualContent) && !utType.conforms(to: .audio) {
            return FileType(kind: .video, identifier: utType.identifier, localizedDescription: utType.localizedDescription ?? "Video")
        }
        if utType.conforms(to: .audio) {
            return FileType(kind: .audio, identifier: utType.identifier, localizedDescription: utType.localizedDescription ?? "Audio")
        }
        return FileType(
            kind: .other,
            identifier: utType.identifier,
            localizedDescription: utType.localizedDescription ?? utType.identifier
        )
    }
}
