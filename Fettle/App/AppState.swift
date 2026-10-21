import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var items: [FileItem] = []
    var selectedItemIDs: Set<UUID> = []
    var settings = AppSettings() {
        didSet {
            jobManager.maxConcurrentJobs = settings.maxConcurrentJobs
            dragMonitor.settings = settings
        }
    }
    var toolStatuses: [KnownTool: ToolStatus] = [:]
    var isActionPickerPresented = false
    var statusMessage = "Drop files onto the window, or drag from Finder and press Shift."
    var lastCompletedJob: Job? = nil
    private var completedJobAutoDismissTask: Task<Void, Never>? = nil

    let detector = FileTypeDetector()
    let tools = ToolAvailability()
    let dragMonitor: DragInteractionMonitor
    let floatingPanel = FloatingPanelController()
    let registry = ActionRegistry()
    let jobManager = JobManager()

    init() {
        let monitor = DragInteractionMonitor(settings: AppSettings())
        self.dragMonitor = monitor
        monitor.onEscape = { [weak self] in
            Task { @MainActor in
                self?.closeRadialMenu()
            }
        }
        monitor.onStateChanged = { [weak self] in
            Task { @MainActor in
                self?.updateFloatingPanel()
            }
        }
        monitor.start()
        refreshTools()
        jobManager.maxConcurrentJobs = settings.maxConcurrentJobs
        jobManager.outputFolderProvider = { [weak self] in
            self?.outputFolder ?? OutputManager.resolvedOutputFolder(from: AppSettings())
        }
        jobManager.onJobCompleted = { [weak self] job in
            Task { @MainActor in
                guard let self else { return }
                self.completedJobAutoDismissTask?.cancel()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    self.lastCompletedJob = job
                }
                let outNames = job.outputURLs.map(\.lastPathComponent).joined(separator: ", ")
                let detail = outNames.isEmpty ? "" : " → \(outNames)"
                self.statusMessage = "✓ \(job.action.title) completed\(detail)"

                NSSound(named: "Glass")?.play()

                self.completedJobAutoDismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if self.lastCompletedJob?.id == job.id {
                            self.lastCompletedJob = nil
                        }
                    }
                }
            }
        }
        jobManager.onJobFailed = { [weak self] job in
            Task { @MainActor in
                guard let self else { return }
                self.statusMessage = "✕ \(job.action.title) failed: \(job.errorMessage ?? "Error")"
            }
        }
    }

    func revealOutputInFinder(for job: Job) {
        let urlsToReveal = !job.outputURLs.isEmpty ? job.outputURLs : job.inputFiles.map(\.url)
        guard !urlsToReveal.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urlsToReveal)
    }

    func dismissCompletedToast() {
        completedJobAutoDismissTask?.cancel()
        completedJobAutoDismissTask = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            lastCompletedJob = nil
        }
    }

    var selectedItems: [FileItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var outputFolder: URL {
        OutputManager.resolvedOutputFolder(from: settings)
    }

    func refreshTools() {
        toolStatuses = tools.snapshot()
    }

    func addDroppedURLs(_ urls: [URL]) {
        var appended: [FileItem] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !items.contains(where: { $0.url == standardized }) else { continue }
            let values = try? standardized.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let fileSize = values?.fileSize.map { Int64($0) }
            let isDir = values?.isDirectory ?? false
            appended.append(FileItem(
                url: standardized,
                type: detector.detect(url: standardized),
                fileSize: fileSize,
                isDirectory: isDir
            ))
        }
        items.append(contentsOf: appended)
        if !appended.isEmpty {
            statusMessage = "Added \(appended.count) file(s)."
        }
    }

    func removeItems(withIDs ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        selectedItemIDs.subtract(ids)
        statusMessage = "Removed \(ids.count) file(s)."
    }

    func clearSelection() {
        items.removeAll()
        selectedItemIDs.removeAll()
        statusMessage = "Selection cleared."
    }

    func availableActions(ringMode: ActionRingMode? = nil, targets: [FileItem]? = nil) -> [ConversionAction] {
        let actualTargets = targets ?? (selectedItems.isEmpty ? items : selectedItems)
        return registry.actions(for: actualTargets, toolStatuses: toolStatuses, ringMode: ringMode)
    }

    func runAction(_ action: ConversionAction, targets: [FileItem]? = nil) {
        let actualTargets = targets ?? (selectedItems.isEmpty ? items : selectedItems)
        guard !actualTargets.isEmpty else { return }
        _ = jobManager.enqueue(action: action, inputFiles: actualTargets)
        statusMessage = "Queued: \(action.title) on \(actualTargets.count) file(s)"
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

    func closeRadialMenu() {
        dragMonitor.cancelLatch()
        dragMonitor.clearSnapshot()
        floatingPanel.hide()
    }

    func openRadialMenuForSelection(mode: ActionRingMode = .conversion) {
        let targets = selectedItems.isEmpty ? items : selectedItems
        guard !targets.isEmpty else {
            statusMessage = "Select or load files first to open Radial Menu."
            return
        }
        let point = NSEvent.mouseLocation
        floatingPanel.show(at: point, size: NSSize(width: 350, height: 350)) {
            RadialMenuView(
                mode: mode,
                targets: targets,
                onSelect: { [weak self] action in
                    guard let self else { return }
                    self.dragMonitor.suppressUntilModifiersReleased(cooldownSeconds: 1.0)
                    self.closeRadialMenu()
                    self.runAction(action, targets: targets)
                },
                onDismiss: { [weak self] in
                    self?.dragMonitor.suppressUntilModifiersReleased(cooldownSeconds: 0.5)
                    self?.closeRadialMenu()
                }
            )
            .environment(self)
        }
    }

    func updateFloatingPanel() {
        guard settings.followPointerWithFloatingPanel, let mode = dragMonitor.latchedMode else {
            floatingPanel.hide()
            return
        }

        dragMonitor.snapshotFileURLsIfNeeded()
        let urls = dragMonitor.snapshotURLs
        let targets: [FileItem]
        if !urls.isEmpty {
            targets = urls.map { FileItem(url: $0, type: self.detector.detect(url: $0)) }
        } else {
            targets = selectedItems.isEmpty ? items : selectedItems
        }

        floatingPanel.show(at: dragMonitor.pointer, size: NSSize(width: 350, height: 350)) {
            RadialMenuView(
                mode: mode,
                targets: targets,
                onSelect: { [weak self] action in
                    guard let self else { return }
                    self.dragMonitor.suppressUntilModifiersReleased(cooldownSeconds: 1.0)
                    self.closeRadialMenu()
                    self.runAction(action, targets: targets)
                },
                onDismiss: { [weak self] in
                    self?.dragMonitor.suppressUntilModifiersReleased(cooldownSeconds: 0.5)
                    self?.closeRadialMenu()
                }
            )
            .environment(self)
        }
    }
}
