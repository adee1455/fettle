import Foundation

struct OutputManager: Sendable {
    /// Resolve output folder from settings bookmark, falling back to ~/Downloads/QuickKit Output.
    static func resolvedOutputFolder(from settings: AppSettings) -> URL {
        if let bookmark = settings.outputFolderBookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if !stale { return url }
            }
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("QuickKit Output", isDirectory: true)
    }

    /// Generate a non-colliding filename.
    static func nonCollidingURL(for basename: String, extension ext: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let base = ext.isEmpty
            ? directory.appendingPathComponent(basename)
            : directory.appendingPathComponent(basename).appendingPathExtension(ext)
        guard fm.fileExists(atPath: base.path) else { return base }

        for i in 1...999 {
            let candidate = ext.isEmpty
                ? directory.appendingPathComponent("\(basename) (\(i))")
                : directory.appendingPathComponent("\(basename) (\(i))").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }

        // Fallback: UUID suffix
        let suffix = UUID().uuidString.prefix(8)
        return ext.isEmpty
            ? directory.appendingPathComponent("\(basename)-\(suffix)")
            : directory.appendingPathComponent("\(basename)-\(suffix)").appendingPathExtension(ext)
    }

    /// Convenience to resolve a non-colliding destination URL given an input file URL.
    static func destinationURL(for sourceURL: URL, targetExtension: String, in directory: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return nonCollidingURL(for: baseName, extension: targetExtension, in: directory)
    }
}
