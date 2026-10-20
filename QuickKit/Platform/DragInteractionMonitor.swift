import AppKit
import CoreGraphics
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
    var onEscape: () -> Void

    private var lastSeenChangeCount: Int
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var modifierPoll: Timer?
    private var wasEscapeDown = false
    private let pasteboard = NSPasteboard(name: .drag)

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

        // 5. Local Escape key monitor (when app has key window)
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
        // Checks global Escape key state (keycode 53) and mouse dragging state
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
        clearSnapshot()
        lastEventDescription = "Latch cancelled"
    }

    func snapshotFileURLsIfNeeded() {
        let urls = Self.readFileURLs(from: pasteboard)
        if !urls.isEmpty {
            snapshotURLs = urls
        }
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
        // 1. Global Escape key detection via CGEventSource (virtual keycode 53 = Escape)
        // Operates even when Finder/Desktop is the active application
        let isEscapeDown = CGEventSource.keyState(.combinedSessionState, key: 53)
        if isEscapeDown && !wasEscapeDown {
            wasEscapeDown = true
            if latchedMode != nil {
                cancelLatch()
                onEscape()
                return
            }
        }
        wasEscapeDown = isEscapeDown

        // 2. Mouse dragging state
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
    }

    private func refreshPasteboard(isDragging: Bool) {
        let changeCount = pasteboard.changeCount
        pasteboardChangeCount = changeCount
        hasFileURLType = Self.pasteboardHasFileURLType(pasteboard)

        if isDragging && hasFileURLType {
            if changeCount != lastSeenChangeCount {
                lastSeenChangeCount = changeCount
                let freshURLs = Self.readFileURLs(from: pasteboard)
                if !freshURLs.isEmpty {
                    snapshotURLs = freshURLs
                }
            } else if snapshotURLs.isEmpty {
                let freshURLs = Self.readFileURLs(from: pasteboard)
                if !freshURLs.isEmpty {
                    snapshotURLs = freshURLs
                }
            }
            isLikelyFileDrag = !snapshotURLs.isEmpty
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
            snapshotFileURLsIfNeeded()
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
