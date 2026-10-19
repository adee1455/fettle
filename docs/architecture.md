# QuickKit architecture

QuickKit is a native macOS app (Swift 6, SwiftUI + AppKit). Processing services do not import SwiftUI. Conversion presets live in data so a later Windows port can reuse the same catalogue.

## Layers

- **App** — `QuickKitApp`, `AppState` composition root.
- **Models** — `FileItem`, `FileType`, `AppSettings`, job types (jobs arrive in Milestone 2).
- **Views** — main window, drop zone, action picker, drag HUD, settings.
- **Services** — `FileTypeDetector`, `ToolAvailability`, `MachOReader`. Later: registry, image/media/PDF, `ProcessRunner`, `OutputManager`, `JobManager`.
- **Platform** — `DragInteractionMonitor`, `FloatingPanelController`. Omit on Windows.

## Interaction paths

1. **Primary:** drop files into the main window; Return opens the action picker.
2. **Spike / future radial menu:** public `NSPasteboard.Name.drag` + global left-mouse monitors + polled `NSEvent.modifierFlags`.
3. **Later:** Finder Quick Actions if global drag tracking stays limited.

## Rules

- `Process` with an executable URL and argument array. Never a shell string from user paths.
- Detect Homebrew tools; reject the wrong CPU architecture.
- Never overwrite without confirmation; never delete originals after conversion.
- No cloud uploads, accounts, telemetry, or bundled third-party executables in this phase.

## Milestone 1 status

The drop zone, type detector, tool scanner, drag monitor, floating stub panel, and HUD are in place. Conversion workers, job queue, and the real radial menu are not.
