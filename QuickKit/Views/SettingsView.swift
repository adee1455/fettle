import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Output Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appState.outputFolder.path)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Choose…") {
                            chooseOutputFolder()
                        }

                        if appState.settings.outputFolderBookmark != nil {
                            Button("Reset to Default") {
                                appState.settings.outputFolderBookmark = nil
                            }
                        }
                    }

                    Text("Converted and processed files will be saved here unless configured otherwise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Job Execution") {
                Stepper(
                    "Max concurrent jobs: \(appState.settings.maxConcurrentJobs)",
                    value: $state.settings.maxConcurrentJobs,
                    in: 1...16
                )

                Text("Limits how many background conversion tasks run in parallel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Drag Interaction (Prototype)") {
                Toggle("Show drag spike HUD", isOn: $state.settings.showDragSpikeHUD)
                Toggle("Follow pointer with floating ring stub", isOn: $state.settings.followPointerWithFloatingPanel)
            }

            Section("Modifier Mappings") {
                Picker("Conversion", selection: $state.settings.conversionModifier) {
                    ForEach(ModifierChoice.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Editing", selection: $state.settings.editingModifier) {
                    ForEach(ModifierChoice.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("File Actions", selection: $state.settings.fileActionModifier) {
                    ForEach(ModifierChoice.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Text("Modifiers polled during active Finder drag gestures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 380)
        .onChange(of: appState.settings) { _, newValue in
            appState.dragMonitor.settings = newValue
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        panel.message = "Choose an output directory for QuickKit files"

        if panel.runModal() == .OK, let url = panel.url {
            let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            appState.settings.outputFolderBookmark = bookmark
        }
    }
}
