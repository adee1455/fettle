import AppKit
import SwiftUI

struct RadialMenuView: View {
    @Environment(AppState.self) private var appState
    var mode: ActionRingMode
    var targets: [FileItem]
    var onSelect: (ConversionAction) -> Void
    var onDismiss: () -> Void

    @State private var hoveredAction: ConversionAction?
    @State private var appearAnimation = false

    private let ringRadius: CGFloat = 112
    private let centerSize: CGFloat = 114
    private let nodeSize: CGFloat = 52
    private let canvasSize: CGFloat = 340

    var body: some View {
        let actions = appState.availableActions(ringMode: mode)

        ZStack {
            // Outer subtle boundary ring
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5)
                .frame(width: canvasSize - 20, height: canvasSize - 20)
                .background(Circle().fill(.ultraThinMaterial.opacity(0.85)))
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)

            // Connecting guides
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let angle = angleForIndex(index, total: actions.count)
                let x = cos(angle) * ringRadius
                let y = sin(angle) * ringRadius

                Path { path in
                    path.move(to: CGPoint(x: canvasSize / 2, y: canvasSize / 2))
                    path.addLine(to: CGPoint(x: canvasSize / 2 + x, y: canvasSize / 2 + y))
                }
                .stroke(
                    hoveredAction?.id == action.id ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
            }

            // Center Hub
            centerHub(actions: actions)

            // Radial Action Nodes
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                radialNode(action: action, index: index, total: actions.count)
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .scaleEffect(appearAnimation ? 1.0 : 0.82)
        .opacity(appearAnimation ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                appearAnimation = true
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    // MARK: - Center Hub

    private func centerHub(actions: [ConversionAction]) -> some View {
        VStack(spacing: 4) {
            if let hovered = hoveredAction {
                Image(systemName: hovered.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                Text(hovered.title)
                    .font(.caption.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)

                if !hovered.subtitle.isEmpty {
                    Text(hovered.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(mode.title)
                    .font(.subheadline.weight(.bold))

                Text("\(targets.count) file\(targets.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if actions.isEmpty {
                    Text("No actions")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("Hover or click")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss (Escape)")
                .padding(.top, 2)
            }
        }
        .frame(width: centerSize, height: centerSize)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(
            Circle().strokeBorder(
                hoveredAction != nil ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.2),
                lineWidth: 1.5
            )
        )
        .shadow(color: .black.opacity(0.15), radius: 6)
    }

    // MARK: - Radial Action Node

    private func radialNode(action: ConversionAction, index: Int, total: Int) -> some View {
        let angle = angleForIndex(index, total: total)
        let x = cos(angle) * ringRadius
        let y = sin(angle) * ringRadius
        let isHovered = hoveredAction?.id == action.id
        let isToolAvailable = isToolReady(action)

        return Button {
            if isToolAvailable {
                onSelect(action)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.85))
                    .frame(width: nodeSize, height: nodeSize)
                    .overlay(
                        Circle().strokeBorder(
                            isHovered ? Color.white : Color.white.opacity(0.25),
                            lineWidth: isHovered ? 2 : 1
                        )
                    )
                    .shadow(color: isHovered ? Color.accentColor.opacity(0.5) : Color.black.opacity(0.12), radius: isHovered ? 8 : 4)

                Image(systemName: action.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isHovered ? Color.white : (isToolAvailable ? Color.primary : Color.secondary))

                // Shortcut number badge
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.accentColor : Color.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(isHovered ? Color.white : Color.black.opacity(0.6)))
                        .offset(x: 18, y: -18)
                }

                if !isToolAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .offset(x: -16, y: -16)
                }
            }
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!isToolAvailable)
        .offset(x: x, y: y)
        .onHover { hovering in
            if hovering {
                hoveredAction = action
            } else if hoveredAction?.id == action.id {
                hoveredAction = nil
            }
        }
    }

    private func angleForIndex(_ index: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let step = (2.0 * CGFloat.pi) / CGFloat(total)
        return -CGFloat.pi / 2.0 + CGFloat(index) * step
    }

    private func isToolReady(_ action: ConversionAction) -> Bool {
        guard let tool = action.requiredTool else { return true }
        return appState.toolStatuses[tool]?.isUsable == true
    }
}
