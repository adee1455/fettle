import Foundation

struct ConversionAction: Identifiable, Equatable, Hashable, Sendable {
    let id: String                          // e.g. "png-to-jpeg"
    let title: String                       // "PNG → JPEG"
    let subtitle: String                    // "Lossy, Quality 85%"
    let systemImage: String                 // SF Symbol name
    let ringMode: ActionRingMode            // .conversion / .editing / .fileActions
    let applicableKinds: Set<FileKind>      // e.g. [.image]
    let requiredTool: KnownTool?            // nil = uses system frameworks
    let minSelection: Int                   // 1
    let maxSelection: Int?                  // nil = unlimited
}
