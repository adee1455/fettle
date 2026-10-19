import SwiftUI

@main
struct QuickKitApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("QuickKit", id: "main") {
            MainWindow()
                .environment(appState)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 880, height: 640)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Radial Menu") {
                    appState.openRadialMenuForSelection()
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Open Action Picker") {
                    appState.openActionPicker()
                }
                .keyboardShortcut(.return, modifiers: [])
                Button("Clear Files") {
                    appState.clearSelection()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
