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
    let sourceExtensions: Set<String>?      // e.g. ["png"]
    let excludedExtensions: Set<String>?    // e.g. ["webp"]
    let isSuggested: Bool                   // Displayed with priority badge in UI
    let priority: Int                       // Sorting priority: lower values rank first
    let targetFormat: String?               // e.g. "WEBP", "PDF", "JPEG"

    init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        ringMode: ActionRingMode,
        applicableKinds: Set<FileKind>,
        requiredTool: KnownTool? = nil,
        minSelection: Int = 1,
        maxSelection: Int? = nil,
        sourceExtensions: Set<String>? = nil,
        excludedExtensions: Set<String>? = nil,
        isSuggested: Bool = false,
        priority: Int = 100,
        targetFormat: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.ringMode = ringMode
        self.applicableKinds = applicableKinds
        self.requiredTool = requiredTool
        self.minSelection = minSelection
        self.maxSelection = maxSelection
        self.sourceExtensions = sourceExtensions
        self.excludedExtensions = excludedExtensions
        self.isSuggested = isSuggested
        self.priority = priority
        self.targetFormat = targetFormat
    }
}
