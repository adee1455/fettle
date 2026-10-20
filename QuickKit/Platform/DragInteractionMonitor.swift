import AppKit
import Foundation

/// Public-API Finder-drag detector: drag pasteboard + global mouse & modifier monitors.
/// Does not require Accessibility permissions or private APIs.
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
    private var globalFlagsMonitor: Any?
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

        // 1. Mouse Dragged
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDragged()
            }
        }

        // 2. Mouse Up
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseUp()
            }
        }

        // 3. Global modifier flags (detect Shift pressed during drag from Finder/Desktop)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] _ in
            Task { @MainActor in
                self?.refreshModifiers()
            }
        }

        // 4. Local modifier flags
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.refreshModifiers()
            }
            return event
        }

        // 5. Escape key dismissal
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

        // 6. High-responsiveness polling timer (Tangerine-style dual monitor)
        modifierPoll = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollState()
            }
        }

        lastEventDescription = "Monitors installed"
    }

    func stop() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }

        dragMonitor = nil
        upMonitor = nil
        globalFlagsMonitor = nil
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

    private func pollState() {
        let isMouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        if isMouseDown {
            pointer = NSEvent.mouseLocation
            refreshPasteboard(isDragging: true)
            refreshModifiers()
        } else if isLeftMouseDragging {
            handleMouseUp()
        }
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
        // Keep latchedMode so the user can interact/confirm from HUD or click to select
    }

    private func refreshPasteboard(isDragging: Bool) {
        let changeCount = pasteboard.changeCount
        pasteboardChangeCount = changeCount
        hasFileURLType = Self.pasteboardHasFileURLType(pasteboard)

        if isDragging && changeCount != lastSeenChangeCount && hasFileURLType {
            lastSeenChangeCount = changeCount
            isLikelyFileDrag = true
            snapshotURLs = []
        } else if isDragging && hasFileURLType && changeCount == lastSeenChangeCount {
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
            if snapshotURLs.isEmpty {
                snapshotFileURLsIfNeeded()
            }
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
