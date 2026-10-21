import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var isTargeted: Bool
    var fileCount: Int

    var body: some View {
        Group {
            if fileCount == 0 {
                emptyDropZone
            } else {
                compactDropBanner
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: fileCount == 0)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File drop zone")
        .accessibilityHint("Drop files from Finder to add them")
    }

    private var emptyDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "square.and.arrow.down")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .scaleEffect(isTargeted ? 1.15 : 1.0)

            Text(isTargeted ? "Drop files to add" : "Drop files here")
                .font(.headline)
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)

            Text("Drag & drop files from Finder · Or select files and hold Shift")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: isTargeted ? [] : [6, 5])
                )
        )
    }

    private var compactDropBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)

            Text(isTargeted ? "Drop to add more files" : "Drop more files to add to selection")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)

            Spacer()

            Text("\(fileCount) loaded")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [5, 4])
                )
        )
    }
}
