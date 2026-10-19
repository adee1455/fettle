import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NavigationSection: String, Hashable, CaseIterable {
    case files
    case jobs
    case tools

    var title: String {
        switch self {
        case .files: "Files"
        case .jobs: "Jobs"
        case .tools: "Tools"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "doc.on.doc"
        case .jobs: "gearshape.arrow.triangle.2.circlepath"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: NavigationSection = .files
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationTitle("QuickKit")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.openRadialMenuForSelection()
                } label: {
                    Label("Radial Menu", systemImage: "circle.grid.cross")
                }
                .disabled(appState.items.isEmpty)
                .keyboardShortcut("r", modifiers: [.command])
                .help("Open Radial Menu (⌘R)")

                Button {
                    appState.openActionPicker()
                } label: {
                    Label("Action Picker", systemImage: "sparkles")
                }
                .help("Open Action Picker (Return)")

                Button {
                    appState.clearSelection()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(appState.items.isEmpty)
                .help("Clear all loaded files")

                Button {
                    appState.refreshTools()
                } label: {
                    Label("Refresh Tools", systemImage: "arrow.clockwise")
                }
                .help("Rescan installed tools")
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

    // MARK: - Sidebar

    private var sidebar: some View {
        List(NavigationSection.allCases, id: \.self, selection: $selectedSection) { section in
            NavigationLink(value: section) {
                HStack {
                    Label(section.title, systemImage: section.systemImage)
                    Spacer()
                    badge(for: section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    }

    @ViewBuilder
    private func badge(for section: NavigationSection) -> some View {
        switch section {
        case .files:
            if !appState.items.isEmpty {
                Text("\(appState.items.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .jobs:
            let active = appState.jobManager.jobs.filter { $0.status == .running || $0.status == .queued }.count
            if active > 0 {
                Text("\(active)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        case .tools:
            let unavailable = appState.toolStatuses.values.filter { !$0.isUsable }.count
            if unavailable > 0 {
                Text("\(unavailable)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedSection {
                case .files:
                    filesView
                case .jobs:
                    JobQueueView()
                case .tools:
                    ToolStatusView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            statusBar
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
    }

    private var filesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            DropZoneView(isTargeted: dropTargeted, fileCount: appState.items.count)

            if appState.settings.showDragSpikeHUD {
                DragSpikeHUD()
            }

            FileListView()
        }
        .padding(16)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            let runningJobs = appState.jobManager.jobs.filter { $0.status == .running }.count
            if runningJobs > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(runningJobs) running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                let folder = appState.outputFolder
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(appState.outputFolder.lastPathComponent)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open output folder in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Drop Handling

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
