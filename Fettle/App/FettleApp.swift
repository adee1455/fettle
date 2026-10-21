import AppKit
import ServiceManagement
import SwiftUI

@main
struct FettleApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Fettle", id: "main") {
            MainWindow()
                .environment(appState)
                .frame(minWidth: 640, minHeight: 460)
        }
        .defaultSize(width: 840, height: 580)
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

        MenuBarExtra {
            menuBarContent
        } label: {
            Image(systemName: "circle.grid.cross")
                .help("Fettle — Drag files & hold Shift")
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    @ViewBuilder
    private var menuBarContent: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        } label: {
            HStack {
                Image(systemName: "macwindow")
                Text("Open Fettle Window")
            }
        }
        .keyboardShortcut("o", modifiers: [.command])

        Divider()

        Text("⚡ Shift-drag in Finder for Radial Menu")

        if let completed = appState.lastCompletedJob, !completed.outputURLs.isEmpty {
            Divider()
            Button {
                appState.revealOutputInFinder(for: completed)
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Show in Finder: \(completed.outputURLs.first?.lastPathComponent ?? "Output")")
                }
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("SMAppService error: \(error)")
                }
            }
        ))

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Quit Fettle") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
