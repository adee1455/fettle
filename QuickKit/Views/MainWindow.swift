import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            List {
                Section("Tools") {
                    toolRow(.ffmpeg)
                    toolRow(.ffprobe)
                    toolRow(.magick)
                    toolRow(.qpdf)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                DropZoneView(isTargeted: dropTargeted, fileCount: appState.items.count)
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)

                if appState.settings.showDragSpikeHUD {
                    DragSpikeHUD()
                }

                fileList
                Text(appState.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("QuickKit")
        .toolbar {
            ToolbarItemGroup {
                Button("Action Picker") { appState.openActionPicker() }
                Button("Clear") { appState.clearSelection() }
                    .disabled(appState.items.isEmpty)
                Button("Refresh tools") { appState.refreshTools() }
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isActionPickerPresented },
            set: { appState.isActionPickerPresented = $0 }
        )) {
            ActionPickerView()
                .environment(appState)
        }
        .onAppear {
            appState.refreshTools()
        }
        .onChange(of: appState.dragMonitor.latchedMode) { _, _ in
            appState.updateFloatingPanel()
        }
        .onChange(of: appState.dragMonitor.pointer.x) { _, _ in
            appState.updateFloatingPanel()
        }
        .onChange(of: appState.settings.followPointerWithFloatingPanel) { _, _ in
            appState.updateFloatingPanel()
        }
    }

    private var fileList: some View {
        Group {
            if appState.items.isEmpty {
                ContentUnavailableView(
                    "No files yet",
                    systemImage: "tray",
                    description: Text("Drop files from Finder, or use a drag plus Shift if tracking is working.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(appState.items) { item in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading) {
                            Text(item.displayName)
                            Text("\(item.type.kind.rawValue) · \(item.type.localizedDescription) · \(item.type.identifier)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(minHeight: 180)
            }
        }
    }

    private func toolRow(_ tool: KnownTool) -> some View {
        let status = appState.toolStatuses[tool] ?? .missing
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(tool.executableName)
                Spacer()
                Text(status.isUsable ? "OK" : "Unavailable")
                    .foregroundStyle(status.isUsable ? .green : .orange)
                    .font(.caption.weight(.semibold))
            }
            Text(status.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !status.isUsable {
                Text(tool.installHint)
                    .font(.caption2.monospaced())
            }
        }
        .padding(.vertical, 4)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var loaded = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loaded = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? URL {
                    url = itemURL
                } else if let nsURL = item as? NSURL {
                    url = nsURL as URL
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in
                    appState.addDroppedURLs([url])
                }
            }
        }
        return loaded
    }
}
