import AppKit
import CoreGraphics
import Foundation

/// Finder drag & selection detector: monitors drag pasteboard, global modifiers, and Finder selection.
/// Zero Accessibility or Input Monitoring permissions required.
@MainActor
@Observable
final class DragInteractionMonitor {
    private(set) var isLeftMouseDragging = false
    private(set) var isLikelyFileDrag = false
    private(set) var pasteboardChangeCount: Int = 0
    private(set) var hasFileURLType = false
    private(set) var modifiers: NSEvent.ModifierFlags = []
    private(set) var latchedMode: ActionRingMode? {
        didSet {
            if oldValue != latchedMode {
                onStateChanged?()
            }
        }
    }
    private(set) var pointer: NSPoint = .zero
    private(set) var snapshotURLs: [URL] = []
    private(set) var lastEventDescription = "Idle"

    var settings: AppSettings
    var onEscape: () -> Void
    var onStateChanged: (() -> Void)?

    private var lastSeenChangeCount: Int
    private var pasteboardChangeCountBeforeMouseDown: Int
    private var wasPrimaryButtonDown = false
    private var wasEscapeDown = false
    private var isSuppressedUntilModifiersReleased = false
    private var suppressUntilDate: Date = .distantPast

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var modifierPoll: Timer?
    private let pasteboard = NSPasteboard(name: .drag)

    init(settings: AppSettings = AppSettings(), onEscape: @escaping () -> Void = {}) {
        self.settings = settings
        self.onEscape = onEscape
        let initialChangeCount = NSPasteboard(name: .drag).changeCount
        self.lastSeenChangeCount = initialChangeCount
        self.pasteboardChangeCountBeforeMouseDown = initialChangeCount
        self.pasteboardChangeCount = initialChangeCount
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

        // 3. Global modifier flags (detect Shift pressed in Finder or Desktop)
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

        // 5. Local Escape key monitor
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.suppressUntilModifiersReleased(cooldownSeconds: 0.5)
                    self?.onEscape()
                }
                return nil
            }
            return event
        }

        // 6. High-responsiveness polling timer (30ms interval) scheduled in .common modes
        // Runs even during active mouse drag tracking across macOS
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierPoll = timer

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

    /// Suppresses radial menu latching until all modifier keys are physically released
    /// plus a safety cooldown window, preventing repeated auto-reopening.
    func suppressUntilModifiersReleased(cooldownSeconds: Double = 1.0) {
        isSuppressedUntilModifiersReleased = true
        suppressUntilDate = Date().addingTimeInterval(cooldownSeconds)
        cancelLatch()
    }

    func snapshotFileURLsIfNeeded() {
        // Only read if currently dragging and a new drag change occurred
        let currentChangeCount = pasteboard.changeCount
        if isLikelyFileDrag && currentChangeCount != pasteboardChangeCountBeforeMouseDown {
            let urls = Self.readFileURLs(from: pasteboard)
            if !urls.isEmpty {
                snapshotURLs = urls
            }
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

    /// Fetches the currently selected file URLs in Finder or Desktop via AppleScript
    static func getFinderSelectedURLs() -> [URL] {
        let script = """
        tell application "Finder"
            set sel to selection as alias list
            set outPaths to {}
            repeat with itemRef in sel
                set end of outPaths to POSIX path of itemRef
            end repeat
            return outPaths
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return [] }
        let result = appleScript.executeAndReturnError(&error)
        guard error == nil else { return [] }

        var urls: [URL] = []
        let count = result.numberOfItems
        if count > 0 {
            for i in 1...count {
                if let path = result.atIndex(i)?.stringValue {
                    urls.append(URL(fileURLWithPath: path).standardizedFileURL)
                }
            }
        } else if let singlePath = result.stringValue {
            urls.append(URL(fileURLWithPath: singlePath).standardizedFileURL)
        }
        return urls
    }

    private func pollState() {
        // 1. Global Escape key detection via CGEventSource (virtual keycode 53 = Escape)
        // Works anywhere on macOS without requiring application activation
        let isEscapeDown = CGEventSource.keyState(.combinedSessionState, key: 53)
        if isEscapeDown && !wasEscapeDown {
            wasEscapeDown = true
            if latchedMode != nil {
                suppressUntilModifiersReleased(cooldownSeconds: 0.5)
                onEscape()
                return
            }
        }
        wasEscapeDown = isEscapeDown

        // 2. Mouse button transitions
        let isMouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        if isMouseDown && !wasPrimaryButtonDown {
            // Mouse pressed down: snapshot baseline change count
            wasPrimaryButtonDown = true
            pasteboardChangeCountBeforeMouseDown = pasteboard.changeCount
        } else if !isMouseDown && wasPrimaryButtonDown {
            // Mouse released: end drag
            wasPrimaryButtonDown = false
            handleMouseUp()
        }

        // 3. While mouse is dragging files, track movement & pasteboard updates
        if isMouseDown && isLikelyFileDrag {
            let newPointer = NSEvent.mouseLocation
            if abs(newPointer.x - pointer.x) > 2 || abs(newPointer.y - pointer.y) > 2 {
                pointer = newPointer
                if latchedMode != nil {
                    onStateChanged?()
                }
            }
            refreshPasteboard(isDragging: true)
            refreshModifiers()
        }
    }

    private func handleMouseDragged() {
        isLeftMouseDragging = true
        let newPointer = NSEvent.mouseLocation
        if isLikelyFileDrag && (abs(newPointer.x - pointer.x) > 2 || abs(newPointer.y - pointer.y) > 2) {
            pointer = newPointer
            if latchedMode != nil {
                onStateChanged?()
            }
        }
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

        // Stale pasteboard rejection: ONLY accept drag items if Finder updated
        // the pasteboard AFTER the primary button was pressed down
        if isDragging && hasFileURLType && changeCount != pasteboardChangeCountBeforeMouseDown {
            lastSeenChangeCount = changeCount
            let freshURLs = Self.readFileURLs(from: pasteboard)
            if !freshURLs.isEmpty {
                snapshotURLs = freshURLs
                isLikelyFileDrag = true
            }
        }

        if !isDragging {
            isLikelyFileDrag = false
        }
    }

    private func refreshModifiers() {
        let cgFlags = CGEventSource.flagsState(.combinedSessionState)
        var flags = NSEvent.modifierFlags
        if cgFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgFlags.contains(.maskControl) { flags.insert(.control) }
        if cgFlags.contains(.maskAlternate) { flags.insert(.option) }
        modifiers = flags

        // Reset suppression once modifier keys have been physically released AND cooldown passed
        let hasActiveModifier = mode(for: flags) != nil
        if !hasActiveModifier {
            if Date() > suppressUntilDate {
                isSuppressedUntilModifiersReleased = false
            }
        }

        // If suppressed after an action execution, ignore until user lifts modifier key
        if isSuppressedUntilModifiersReleased || Date() < suppressUntilDate {
            return
        }

        guard let mapped = mode(for: modifiers) else {
            // Modifier released: if not currently in a mouse drag session, dismiss radial
            if latchedMode != nil && !isLeftMouseDragging {
                cancelLatch()
                onEscape()
            }
            return
        }

        if isLikelyFileDrag && !snapshotURLs.isEmpty {
            // Active file drag session with fresh URLs
            pointer = NSEvent.mouseLocation
            latchedMode = mapped
        } else {
            // Mouse is not dragging: check if Finder/Desktop has files currently selected
            if latchedMode == nil {
                let frontAppId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if frontAppId == "com.apple.finder" {
                    let selected = Self.getFinderSelectedURLs()
                    if !selected.isEmpty {
                        snapshotURLs = selected
                        pointer = NSEvent.mouseLocation
                        latchedMode = mapped
                    }
                }
            } else if latchedMode != mapped {
                latchedMode = mapped
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
