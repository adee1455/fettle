import AppKit
import SwiftUI

struct CompletionToastView: View {
    @Environment(AppState.self) private var appState
    let job: Job

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(job.action.title) Completed")
                    .font(.subheadline.weight(.semibold))

                if !job.outputURLs.isEmpty {
                    Text(outputDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button {
                appState.revealOutputInFinder(for: job)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                    Text("Show in Finder")
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                appState.dismissCompletedToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        )
    }

    private var outputDescription: String {
        if job.outputURLs.count == 1, let first = job.outputURLs.first {
            return first.lastPathComponent
        } else {
            return "\(job.outputURLs.count) files generated in \(job.outputURLs.first?.deletingLastPathComponent().lastPathComponent ?? "folder")"
        }
    }
}
