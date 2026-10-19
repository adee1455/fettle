import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var isTargeted: Bool
    var fileCount: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : (fileCount == 0 ? "square.and.arrow.down" : "doc.on.doc"))
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .scaleEffect(isTargeted ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)

            Text(isTargeted ? "Drop files to add" : (fileCount == 0 ? "Drop files here" : "\(fileCount) file(s) loaded"))
                .font(.headline)
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)

            Text("Drag & drop files from Finder · Or press Return to open Action Picker")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: isTargeted ? [] : [6, 5])
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File drop zone")
        .accessibilityHint("Drop files from Finder to add them")
    }
}
