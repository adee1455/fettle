import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var isTargeted: Bool
    var fileCount: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: fileCount == 0 ? "square.and.arrow.down" : "doc.on.doc")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)
            Text(fileCount == 0 ? "Drop files here" : "\(fileCount) file(s) ready")
                .font(.title3.weight(.semibold))
            Text("Finder drops work even if global drag tracking is unavailable.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File drop zone")
        .accessibilityHint("Drop files from Finder to add them")
    }
}
