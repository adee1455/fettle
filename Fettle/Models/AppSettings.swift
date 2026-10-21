import Foundation

enum ModifierChoice: String, Codable, Equatable, Sendable, CaseIterable {
    case shift
    case command
    case control
    case option
}

struct AppSettings: Codable, Equatable, Sendable {
    var conversionModifier: ModifierChoice = .shift
    var editingModifier: ModifierChoice = .command
    var fileActionModifier: ModifierChoice = .control
    var followPointerWithFloatingPanel: Bool = true
    var outputFolderBookmark: Data? = nil
    var maxConcurrentJobs: Int = 4
}
