import Foundation

enum JobStatus: String, Equatable, Sendable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

@MainActor
@Observable
final class Job: Identifiable {
    let id: UUID
    let action: ConversionAction
    let inputFiles: [FileItem]
    let createdAt: Date

    var status: JobStatus = .queued
    var progress: Double = 0          // 0.0…1.0
    var statusMessage: String = "Queued"
    var errorMessage: String?
    var completedAt: Date?
    var outputURLs: [URL] = []

    var runTask: Task<Void, Never>?

    init(action: ConversionAction, inputFiles: [FileItem]) {
        self.id = UUID()
        self.action = action
        self.inputFiles = inputFiles
        self.createdAt = Date()
    }
}
