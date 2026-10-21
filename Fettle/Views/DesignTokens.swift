import AppKit
import SwiftUI

enum DesignTokens {
    // MARK: - Spacing & Metrics
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 14
    static let spacingLG: CGFloat = 20
    static let spacingXL: CGFloat = 28

    static let cornerRadiusCard: CGFloat = 12
    static let cornerRadiusPill: CGFloat = 20

    // MARK: - Radial Menu Sizing
    static let radialCanvasSize: CGFloat = 350
    static let radialCenterSize: CGFloat = 118
    static let radialNodeSize: CGFloat = 54
    static let radialRingRadius: CGFloat = 118

    // MARK: - Gradients & Styling
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var subtleGlow: Color {
        Color.accentColor.opacity(0.35)
    }

    // MARK: - Haptic Feedback
    @MainActor
    static func playHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }
}
