import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NavigationSection: String, Hashable, CaseIterable {
    case files
    case jobs

    var title: String {
        switch self {
        case .files: "Files"
        case .jobs: "Jobs"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "doc.on.doc"
        case .jobs: "gearshape.arrow.triangle.2.circlepath"
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
        .navigationTitle("Fettle")
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
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedSection {
                    case .files:
                        filesView
                    case .jobs:
                        JobQueueView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let completedJob = appState.lastCompletedJob {
                    CompletionToastView(job: completedJob)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.lastCompletedJob?.id)

            Divider()

            statusBar
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
    }

    private var filesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            DropZoneView(isTargeted: dropTargeted, fileCount: appState.items.count)

            FileListView()
        }
        .padding(16)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.lastCompletedJob != nil ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let completed = appState.lastCompletedJob, !completed.outputURLs.isEmpty {
                Button {
                    appState.revealOutputInFinder(for: completed)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .font(.caption2.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Spacer()

            let runningJobs = appState.jobManager.jobs.filter { $0.status == .running }.count
            if runningJobs > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(runningJobs) running")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9))
                Text("In-Place Output")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
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
