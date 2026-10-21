import AppKit
import SwiftUI

struct FileListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        if appState.items.isEmpty {
            ContentUnavailableView(
                "No files yet",
                systemImage: "tray",
                description: Text("Drop files into the drop zone above, or drag from Finder.")
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(appState.items.count) file(s)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if !appState.selectedItemIDs.isEmpty {
                        Text("(\(appState.selectedItemIDs.count) selected)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Select All") {
                        appState.selectedItemIDs = Set(appState.items.map(\.id))
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)

                    if !appState.selectedItemIDs.isEmpty {
                        Button("Deselect All") {
                            appState.selectedItemIDs.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Button("Remove Selected") {
                            appState.removeItems(withIDs: appState.selectedItemIDs)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 4)

                List(selection: $state.selectedItemIDs) {
                    ForEach(appState.items) { item in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(item.type.kind.rawValue.capitalized)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(kindBadgeColor(item.type.kind).opacity(0.15))
                                        .foregroundStyle(kindBadgeColor(item.type.kind))
                                        .clipShape(Capsule())

                                    Text(item.type.localizedDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if let lastJob = appState.lastCompletedJob,
                               lastJob.inputFiles.contains(where: { $0.id == item.id }),
                               !lastJob.outputURLs.isEmpty {
                                Button {
                                    appState.revealOutputInFinder(for: lastJob)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                        Text(lastJob.outputURLs.first?.lastPathComponent ?? "Converted")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.green)
                                        Image(systemName: "folder")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("Show converted file in Finder")
                            }

                            Text(item.fileSizeFormatted)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.url.path, forType: .string)
                            } label: {
                                Label("Copy Path", systemImage: "doc.on.clipboard")
                            }

                            Divider()

                            Button(role: .destructive) {
                                appState.removeItems(withIDs: [item.id])
                            } label: {
                                Label("Remove from List", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func kindBadgeColor(_ kind: FileKind) -> Color {
        switch kind {
        case .image: .blue
        case .video: .purple
        case .audio: .orange
        case .pdf: .red
        case .document: .indigo
        case .other: .gray
        }
    }
}
