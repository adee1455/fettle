import AppKit
import SwiftUI

struct DragSpikeHUD: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let monitor = appState.dragMonitor
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag spike HUD")
                .font(.headline)
            gridRow("Mouse dragging", yesNo(monitor.isLeftMouseDragging))
            gridRow("Likely file drag", yesNo(monitor.isLikelyFileDrag))
            gridRow("Pasteboard changeCount", "\(monitor.pasteboardChangeCount)")
            gridRow("Has file URL type", yesNo(monitor.hasFileURLType))
            gridRow("Modifiers", modifierSummary(monitor.modifiers))
            gridRow("Latched ring", monitor.latchedMode?.title ?? "None")
            gridRow("Pointer", String(format: "%.0f, %.0f", monitor.pointer.x, monitor.pointer.y))
            gridRow("Snapshot URLs", "\(monitor.snapshotURLs.count)")
            Text(monitor.lastEventDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Snapshot & Reveal") {
                    appState.revealSnapshotFromDrag()
                }
                Button("Cancel latch") {
                    appState.dragMonitor.cancelLatch()
                    appState.floatingPanel.hide()
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.45)))
    }

    private func gridRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospaced())
        }
        .font(.caption)
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private func modifierSummary(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }
}
