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

    private let ringRadius = DesignTokens.radialRingRadius
    private let centerSize = DesignTokens.radialCenterSize
    private let nodeSize = DesignTokens.radialNodeSize
    private let canvasSize = DesignTokens.radialCanvasSize

    var body: some View {
        let actions = appState.availableActions(ringMode: mode, targets: targets)

        ZStack {
            // Dismiss background tap
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }

            // Outer subtle boundary ring
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.5)
                .frame(width: canvasSize - 20, height: canvasSize - 20)
                .background(Circle().fill(.ultraThinMaterial.opacity(0.92)))
                .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 10)

            // Connecting guide lines
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                let angle = angleForIndex(index, total: actions.count)
                let x = cos(angle) * ringRadius
                let y = sin(angle) * ringRadius
                let isHovered = hoveredAction?.id == action.id

                Path { path in
                    path.move(to: CGPoint(x: canvasSize / 2, y: canvasSize / 2))
                    path.addLine(to: CGPoint(x: canvasSize / 2 + x, y: canvasSize / 2 + y))
                }
                .stroke(
                    isHovered ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1),
                    style: StrokeStyle(lineWidth: isHovered ? 2.0 : 1.2, dash: [4, 4])
                )
                .animation(.easeInOut(duration: 0.18), value: isHovered)
            }

            // Center Hub
            centerHub(actions: actions)

            // Radial Action Nodes
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                radialNode(action: action, index: index, total: actions.count)
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .scaleEffect(appearAnimation ? 1.0 : 0.8)
        .opacity(appearAnimation ? 1.0 : 0.0)
        .onAppear {
            if hoveredAction == nil {
                hoveredAction = actions.first(where: { $0.isSuggested }) ?? actions.first
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                appearAnimation = true
            }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            cycleHovered(actions: actions, delta: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            cycleHovered(actions: actions, delta: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            cycleHovered(actions: actions, delta: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            cycleHovered(actions: actions, delta: 1)
            return .handled
        }
        .onKeyPress(.return) {
            if let hovered = hoveredAction {
                onSelect(hovered)
                return .handled
            }
            if let first = actions.first {
                onSelect(first)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { press in
            guard let char = press.characters.first,
                  let num = Int(String(char)),
                  num >= 1 && num <= actions.count else {
                return .ignored
            }
            let action = actions[num - 1]
            if isToolReady(action) {
                DesignTokens.playHapticFeedback()
                onSelect(action)
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Center Hub

    private func centerHub(actions: [ConversionAction]) -> some View {
        VStack(spacing: 3) {
            if let hovered = hoveredAction {
                Image(systemName: hovered.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text(hovered.title)
                    .font(.system(size: 11, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 6)

                if let format = hovered.targetFormat {
                    Text(format)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(Color.accentColor)
                }

                if !hovered.subtitle.isEmpty {
                    Text(hovered.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                // Idle view: display target file info & smart tips
                if let first = targets.first {
                    Image(systemName: systemImageForTarget(first))
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)

                    Text(targets.count == 1 ? first.displayName : "\(targets.count) files")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)

                    Text(first.type.localizedDescription)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .bold))
                }

                if actions.isEmpty {
                    Text("No actions")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else {
                    Text("Drop or press 1-\(min(actions.count, 9))")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss (Escape)")
                .padding(.top, 1)
            }
        }
        .frame(width: centerSize, height: centerSize)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(
            Circle().strokeBorder(
                hoveredAction != nil ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.2),
                lineWidth: 1.5
            )
        )
        .shadow(color: .black.opacity(0.18), radius: 8)
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
                DesignTokens.playHapticFeedback()
                onSelect(action)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isHovered ? AnyShapeStyle(DesignTokens.accentGradient) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.9)))
                    .frame(width: nodeSize, height: nodeSize)
                    .overlay(
                        Circle().strokeBorder(
                            isHovered ? Color.white : (action.isSuggested ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.2)),
                            lineWidth: isHovered ? 2 : (action.isSuggested ? 1.5 : 1)
                        )
                    )
                    .shadow(
                        color: isHovered ? Color.accentColor.opacity(0.55) : Color.black.opacity(0.14),
                        radius: isHovered ? 10 : 4
                    )

                Image(systemName: action.systemImage)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(isHovered ? Color.white : (isToolAvailable ? Color.primary : Color.secondary))

                // Number shortcut badge (1..9)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? Color.accentColor : Color.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(isHovered ? Color.white : Color.black.opacity(0.65)))
                        .offset(x: 18, y: -18)
                }

                // Suggested indicator star
                if action.isSuggested && !isHovered {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: -18, y: -18)
                }

                // Tool missing warning
                if !isToolAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .offset(x: -16, y: 16)
                }
            }
            .contentShape(Circle())
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(!isToolAvailable)
        .offset(x: x, y: y)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
        .onHover { hovering in
            if hovering {
                hoveredAction = action
                DesignTokens.playHapticFeedback()
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

    private func cycleHovered(actions: [ConversionAction], delta: Int) {
        guard !actions.isEmpty else { return }
        let currentIndex = hoveredAction.flatMap { current in actions.firstIndex(where: { $0.id == current.id }) } ?? -1
        let newIndex = (currentIndex + delta + actions.count) % actions.count
        hoveredAction = actions[newIndex]
        DesignTokens.playHapticFeedback()
    }

    private func systemImageForTarget(_ item: FileItem) -> String {
        switch item.type.kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .document: "doc.text"
        case .other: "doc"
        }
    }
}
