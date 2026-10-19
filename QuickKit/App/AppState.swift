import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var items: [FileItem] = []
    var settings = AppSettings()
    var toolStatuses: [KnownTool: ToolStatus] = [:]
    var isActionPickerPresented = false
    var statusMessage = "Drop files onto the window, or drag from Finder and press Shift."

    let detector = FileTypeDetector()
    let tools = ToolAvailability()
    let dragMonitor: DragInteractionMonitor
    let floatingPanel = FloatingPanelController()

    init() {
        let monitor = DragInteractionMonitor(settings: AppSettings())
        self.dragMonitor = monitor
        monitor.start()
        refreshTools()
    }

    func refreshTools() {
        toolStatuses = tools.snapshot()
    }

    func addDroppedURLs(_ urls: [URL]) {
        var appended: [FileItem] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !items.contains(where: { $0.url == standardized }) else { continue }
            appended.append(FileItem(url: standardized, type: detector.detect(url: standardized)))
        }
        items.append(contentsOf: appended)
        if !appended.isEmpty {
            statusMessage = "Added \(appended.count) file(s)."
        }
    }

    func clearSelection() {
        items.removeAll()
        statusMessage = "Selection cleared."
    }

    func revealSnapshotFromDrag() {
        dragMonitor.snapshotFileURLsIfNeeded()
        let urls = dragMonitor.snapshotURLs
        guard let first = urls.first else {
            statusMessage = "No file URLs on the drag pasteboard."
            return
        }
        addDroppedURLs(urls)
        NSWorkspace.shared.activateFileViewerSelecting([first])
        statusMessage = "Revealed \(first.lastPathComponent) from drag snapshot."
    }

    func openActionPicker() {
        isActionPickerPresented = true
    }

    func updateFloatingPanel() {
        guard settings.followPointerWithFloatingPanel, dragMonitor.latchedMode != nil else {
            floatingPanel.hide()
            return
        }
        let mode = dragMonitor.latchedMode
        let count = dragMonitor.hasFileURLType
        floatingPanel.show(at: dragMonitor.pointer) {
            FloatingRingStubView(
                mode: mode,
                fileTypePresent: count,
                fileCountHint: self.dragMonitor.snapshotURLs.count
            )
        }
    }
}
