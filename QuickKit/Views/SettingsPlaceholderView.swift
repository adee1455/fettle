import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Drag interaction") {
                Toggle("Show drag spike HUD", isOn: $appState.settings.showDragSpikeHUD)
                Toggle("Follow pointer with floating stub", isOn: $appState.settings.followPointerWithFloatingPanel)
            }
            Section("Modifier mappings") {
                Picker("Conversion", selection: $appState.settings.conversionModifier) {
                    ForEach(ModifierChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Editing", selection: $appState.settings.editingModifier) {
                    ForEach(ModifierChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("File actions", selection: $appState.settings.fileActionModifier) {
                    ForEach(ModifierChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text("Mappings apply only to the verified drag monitor. They are not claimed for other contexts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 280)
        .onChange(of: appState.settings) { _, newValue in
            appState.dragMonitor.settings = newValue
        }
    }
}
