import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?

    func show<Content: View>(at point: NSPoint, size: NSSize = NSSize(width: 280, height: 220), @ViewBuilder content: () -> Content) {
        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(origin: .zero, size: size)

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }

        panel?.contentView = hosting
        panel?.setContentSize(size)
        position(at: point, size: size)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func position(at point: NSPoint, size: NSSize) {
        guard let panel, let screen = screen(for: point) else { return }
        let visible = screen.visibleFrame
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func screen(for point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
