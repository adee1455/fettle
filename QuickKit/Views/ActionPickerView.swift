import SwiftUI

struct ActionPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedRingMode: ActionRingMode?

    var body: some View {
        let targets = appState.selectedItems.isEmpty ? appState.items : appState.selectedItems

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Action Picker")
                        .font(.title2.weight(.bold))

                    if targets.isEmpty {
                        Text("No files selected. Actions will be available when files are loaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(targetSummary(targets))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            if targets.isEmpty {
                ContentUnavailableView(
                    "No files loaded",
                    systemImage: "tray",
                    description: Text("Drop files into the main window or hold Shift while dragging from Finder.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Filter Picker & Search Bar
                HStack(spacing: 12) {
                    Picker("Category", selection: $selectedRingMode) {
                        Text("All").tag(Optional<ActionRingMode>.none)
                        ForEach(ActionRingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(Optional(mode))
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Search actions…", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .frame(maxWidth: 220)
                }

                // Action list grouped by ring mode
                List {
                    let modes: [ActionRingMode] = selectedRingMode.map { [$0] } ?? ActionRingMode.allCases
                    ForEach(modes, id: \.self) { mode in
                        let modeActions = filteredActions(mode: mode, targets: targets)
                        if !modeActions.isEmpty {
                            Section {
                                ForEach(modeActions) { action in
                                    actionRow(action: action)
                                }
                            } header: {
                                Text(mode.title.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
    }

    private func actionRow(action: ConversionAction) -> some View {
        let toolReady = isToolAvailable(action: action)

        return Button {
            if toolReady {
                DesignTokens.playHapticFeedback()
                appState.runAction(action)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(toolReady ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                        .frame(width: 34, height: 34)

                    Image(systemName: action.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(toolReady ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(action.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(toolReady ? .primary : .secondary)

                        if let format = action.targetFormat {
                            Text(format)
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                                .foregroundStyle(Color.accentColor)
                        }

                        if action.isSuggested {
                            Text("SUGGESTED")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                                .foregroundStyle(.orange)
                        }
                    }

                    if !action.subtitle.isEmpty {
                        Text(action.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !toolReady, let tool = action.requiredTool {
                    Text("Requires \(tool.executableName)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!toolReady)
    }

    private func filteredActions(mode: ActionRingMode, targets: [FileItem]) -> [ConversionAction] {
        let matching = appState.registry.actions(
            for: targets,
            toolStatuses: appState.toolStatuses,
            ringMode: mode
        )

        guard !searchText.isEmpty else { return matching }

        return matching.filter { action in
            action.title.localizedCaseInsensitiveContains(searchText) ||
            action.subtitle.localizedCaseInsensitiveContains(searchText) ||
            (action.targetFormat?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func isToolAvailable(action: ConversionAction) -> Bool {
        guard let tool = action.requiredTool else { return true }
        return appState.toolStatuses[tool]?.isUsable == true
    }

    private func targetSummary(_ targets: [FileItem]) -> String {
        let isSelection = !appState.selectedItems.isEmpty
        let prefix = isSelection ? "Selected \(targets.count)" : "All \(targets.count)"
        let kinds = Dictionary(grouping: targets, by: { $0.type.localizedDescription })
            .map { "\($0.value.count) \($0.key)" }
            .joined(separator: ", ")
        return "\(prefix) file(s): \(kinds)"
    }
}
