import SwiftUI

struct ActionPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Action picker")
                .font(.title2.weight(.semibold))
            if appState.items.isEmpty {
                Text("No files selected. Drop files into the main window first.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(appState.items.count) file(s). Conversion, media, and PDF actions land in later milestones.")
                    .foregroundStyle(.secondary)
                List(appState.items) { item in
                    VStack(alignment: .leading) {
                        Text(item.displayName)
                        Text("\(item.type.kind.rawValue) · \(item.type.localizedDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
    }
}
