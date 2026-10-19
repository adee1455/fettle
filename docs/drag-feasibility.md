# External Drag Feasibility & Spike Report

## Executive Summary

The feasibility spike investigated whether a macOS utility can detect when a user begins dragging files from Finder, monitor modifier key presses (e.g. Shift, Command, Control), and present a floating contextual HUD/menu near the cursor **without requiring Accessibility or Input Monitoring permissions**, and **without using private Apple APIs**.

**Result: FEASIBLE with documented edge cases and caveats.**
The public combination of `NSPasteboard(name: .drag)`, `changeCount` tracking, and `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp])` reliably identifies active Finder drag operations while keeping the application fully compliant with App Store sandbox constraints if needed. QuickKit also retains the primary main-window drop zone as an unconstrained fallback.

---

## Technical Mechanism & Architecture

### Public APIs Employed
1. **`NSPasteboard(name: .drag)`**:
   When Finder initiates a file drag, it populates the system `.drag` pasteboard and increments `pasteboard.changeCount`.
   Declared types include `kUTTypeFileURL` (`public.file-url`) or `NSFilenamesPboardType`.
2. **Global Mouse Monitors (`NSEvent.addGlobalMonitorForEvents`)**:
   - `leftMouseDragged`: Tracks pointer movement globally across desktop and non-active apps without requiring Accessibility.
   - `leftMouseUp`: Signals when a drag gesture has completed or dropped.
3. **Modifier Key Polling (`NSEvent.modifierFlags`)**:
   Global key monitors (`keyDown`, `flagsChanged`) require Input Monitoring permissions. However, **`NSEvent.modifierFlags` can be queried at any time** without special permissions. Polling it during active drag events and via a low-frequency (50ms) timer captures modifier transitions (Shift, Command, Control) accurately.
4. **Non-Activating Floating Panel (`NSPanel`)**:
   `NSPanel` initialized with `.nonactivatingPanel` and styleMask `.borderless` allows displaying UI directly beneath the cursor without stealing focus or interrupting Finder's in-flight drag session.

### Permission Policy Matrix

| Permission | Required in QuickKit? | Reason | Fallback if Unavailable |
|---|---|---|---|
| **Accessibility** | **No** | Global event taps are avoided. | Standard window drop zone. |
| **Input Monitoring** | **No** | `NSEvent.modifierFlags` polling used instead of `CGEventTap`. | Standard window drop zone. |
| **Full Disk Access** | **No** | Only user-dragged URLs are resolved. | Security-scoped bookmarks / standard drag drop. |

---

## Comparison: Tangerine (v2.0.2) User-Visible Analysis

*Note: In accordance with clean-room guidelines, Tangerine was inspected strictly from public metadata and user-visible behavior. No proprietary code or assets were extracted.*

- **Sandbox & Entitlements**:
  Tangerine (`com.th.Tangerine`) runs sandboxed with:
  `com.apple.security.app-sandbox = true`
  `com.apple.security.files.user-selected.read-write = true`
  `com.apple.security.network.client = true`
  **Crucially: Zero Accessibility (`com.apple.security.temporary-exception.apple-events`) and Zero Input Monitoring entitlements.**
- **User-Visible Behavior Observed**:
  1. Dragging a file from Finder does not immediately show an interface.
  2. Pressing a modifier (e.g. `Shift`) while dragging brings up an overlay ring at the cursor.
  3. Releasing `Shift` latches the ring in place or keeps it tracking mouse motion until drop or cancellation.
  4. Hitting `Escape` clears the overlay without cancelling Finder's native drag session.
- **Findings**:
  This confirms that user-visible drag detection and modifier latching can be accomplished entirely through public pasteboard observation and non-activating overlays.

---

## Test Matrix & Results

| # | Test Scenario | Expected Outcome | Result | Notes |
|---|---|---|---|---|
| 1 | **Finder File Drag** | HUD reflects `isLeftMouseDragging = true`, `hasFileURLType = true`, `changeCount` incremented. | **PASS** | Finder writes to `.drag` pasteboard within milliseconds of drag initiation. |
| 2 | **Modifier Detection** | Pressing `Shift` / `Cmd` / `Ctrl` updates HUD `Modifiers` and latches mode. | **PASS** | Polled `NSEvent.modifierFlags` successfully detects changes during drag. |
| 3 | **Escape Key Cancellation** | Pressing Escape releases latched ring and dismisses floating panel. | **PASS** | Handled locally via `NSEvent.addLocalMonitorForEvents`. |
| 4 | **URL Snapshot on Action** | URLs captured only when user triggers action, not continuously during drag. | **PASS** | Prevents pasteboard thrashing and sandbox access delays. |
| 5 | **Negative Test: Window Drag** | Dragging a window title bar does not trigger `hasFileURLType`. | **PASS** | Window dragging does not write file URLs to `.drag` pasteboard. |
| 6 | **Negative Test: Text Drag** | Dragging plain text does not trigger `hasFileURLType`. | **PASS** | Drag pasteboard contains string/RTF types, but no `.fileURL`. |
| 7 | **Main Window Drop Zone** | Dropping files directly onto window `DropZoneView` accepts files. | **PASS** | Primary workflow functions independently of external drag monitor. |

---

## Limitations & Engineering Recommendations

1. **Pasteboard Contention / Drop Timing**:
   Reading pasteboard objects eagerly while a drag is in flight can interfere with certain target apps. Therefore, QuickKit only inspects `pasteboard.types` (checking for `.fileURL`) during the drag, and delays `readObjects(forClasses: [NSURL.self])` until an action is explicitly invoked or confirmed.
2. **Multi-Display Edge Cases**:
   `FloatingPanelController` clamps panel positioning to `NSScreen.visibleFrame` for the active screen where `NSEvent.mouseLocation` resides to prevent the panel from spawning off-screen.
3. **Primary vs Secondary Path**:
   Because external drag tracking relies on polling and heuristics, the **Main Window Drop Zone** remains the core, fully verified product workflow. The drag monitor HUD serves as the verified prototype for the future radial menu (Milestone 6).
