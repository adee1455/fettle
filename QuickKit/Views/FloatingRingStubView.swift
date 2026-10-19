import SwiftUI

struct FloatingRingStubView: View {
    var mode: ActionRingMode?
    var fileTypePresent: Bool
    var fileCountHint: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.grid.cross")
                .font(.title)
            Text(mode?.title ?? "Actions")
                .font(.headline)
            Text(fileTypePresent ? "File drag detected" : "Waiting for file URLs")
                .font(.caption)
                .foregroundStyle(.secondary)
            if fileCountHint > 0 {
                Text("\(fileCountHint) snapshot URL(s)")
                    .font(.caption2)
            }
            Text("Original QuickKit stub — not a product radial menu yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(width: 260, height: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.2)))
    }
}
