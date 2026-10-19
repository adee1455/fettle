import AppKit
import Foundation

/// Public-API Finder-drag detector: drag pasteboard + global mouse monitors.
/// Does not use Accessibility, Input Monitoring, event taps, or private dragging sessions.
@MainActor
@Observable
final class DragInteractionMonitor {
    private(set) var isLeftMouseDragging = false
    private(set) var isLikelyFileDrag = false
    private(set) var pasteboardChangeCount: Int = 0
    private(set) var hasFileURLType = false
    private(set) var modifiers: NSEvent.ModifierFlags = []
    private(set) var latchedMode: ActionRingMode?
    private(set) var pointer: NSPoint = .zero
    private(set) var snapshotURLs: [URL] = []
    private(set) var lastEventDescription = "Idle"

    var settings: AppSettings

    private var lastSeenChangeCount: Int
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var modifierPoll: Timer?
    private let pasteboard = NSPasteboard(name: .drag)
    private let onEscape: () -> Void

    init(settings: AppSettings = AppSettings(), onEscape: @escaping () -> Void = {}) {
        self.settings = settings
        self.onEscape = onEscape
        self.lastSeenChangeCount = NSPasteboard(name: .drag).changeCount
        self.pasteboardChangeCount = lastSeenChangeCount
        self.pointer = NSEvent.mouseLocation
        self.modifiers = NSEvent.modifierFlags
    }

    func start() {
        stop()
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDragged()
            }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseUp()
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.refreshModifiers()
            }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.cancelLatch()
                    self?.onEscape()
                }
                return nil
            }
            return event
        }
        modifierPoll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshModifiers()
            }
        }
        lastEventDescription = "Monitors installed"
    }

    func stop() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        dragMonitor = nil
        upMonitor = nil
        localFlagsMonitor = nil
        localKeyMonitor = nil
        modifierPoll?.invalidate()
        modifierPoll = nil
    }

    func cancelLatch() {
        latchedMode = nil
        lastEventDescription = "Latch cancelled"
    }

    func snapshotFileURLsIfNeeded() {
        guard snapshotURLs.isEmpty else { return }
        snapshotURLs = Self.readFileURLs(from: pasteboard)
    }

    func clearSnapshot() {
        snapshotURLs = []
    }

    static func pasteboardHasFileURLType(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        if types.contains(.fileURL) { return true }
        return types.contains { $0.rawValue == "public.file-url" || $0.rawValue == "NSFilenamesPboardType" }
    }

    static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            return urls.map(\.standardizedFileURL)
        }
        return []
    }

    private func handleMouseDragged() {
        isLeftMouseDragging = true
        pointer = NSEvent.mouseLocation
        refreshPasteboard(isDragging: true)
        refreshModifiers()
        lastEventDescription = "leftMouseDragged"
    }

    private func handleMouseUp() {
        isLeftMouseDragging = false
        isLikelyFileDrag = false
        lastEventDescription = "leftMouseUp"
        // Keep latchedMode so the user can confirm from the HUD after the Finder drag ends.
    }

    private func refreshPasteboard(isDragging: Bool) {
        let changeCount = pasteboard.changeCount
        pasteboardChangeCount = changeCount
        hasFileURLType = Self.pasteboardHasFileURLType(pasteboard)
        if isDragging, changeCount != lastSeenChangeCount, hasFileURLType {
            lastSeenChangeCount = changeCount
            isLikelyFileDrag = true
            snapshotURLs = []
        } else if isDragging, hasFileURLType, changeCount == lastSeenChangeCount {
            // Finder often updates the pasteboard a few milliseconds after the first dragged event.
            isLikelyFileDrag = true
        }
        if !isDragging {
            isLikelyFileDrag = false
        }
    }

    private func refreshModifiers() {
        modifiers = NSEvent.modifierFlags
        pointer = NSEvent.mouseLocation
        guard isLikelyFileDrag || latchedMode != nil else { return }

        if let mapped = mode(for: modifiers) {
            latchedMode = mapped
        }
    }

    private func mode(for flags: NSEvent.ModifierFlags) -> ActionRingMode? {
        if matches(settings.conversionModifier, flags: flags) { return .conversion }
        if matches(settings.editingModifier, flags: flags) { return .editing }
        if matches(settings.fileActionModifier, flags: flags) { return .fileActions }
        return nil
    }

    private func matches(_ choice: ModifierChoice, flags: NSEvent.ModifierFlags) -> Bool {
        switch choice {
        case .shift: flags.contains(.shift)
        case .command: flags.contains(.command)
        case .control: flags.contains(.control)
        case .option: flags.contains(.option)
        }
    }
}
