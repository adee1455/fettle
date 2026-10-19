import SwiftUI

struct ActionPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedRingMode: ActionRingMode?

    var body: some View {
        let targets = appState.selectedItems.isEmpty ? appState.items : appState.selectedItems
        let allActions = appState.registry.actions

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
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
                    description: Text("Drop files into the main window to pick actions.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Filter Picker
                HStack {
                    Picker("Category", selection: $selectedRingMode) {
                        Text("All").tag(Optional<ActionRingMode>.none)
                        ForEach(ActionRingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(Optional(mode))
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Spacer()

                    TextField("Search actions…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                // Action list grouped by ring mode
                List {
                    let modes: [ActionRingMode] = selectedRingMode.map { [$0] } ?? ActionRingMode.allCases
                    ForEach(modes, id: \.self) { mode in
                        let modeActions = filteredActions(allActions: allActions, mode: mode, targets: targets)
                        if !modeActions.isEmpty {
                            Section(mode.title) {
                                ForEach(modeActions) { action in
                                    actionRow(action: action, targets: targets)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
    }

    private func actionRow(action: ConversionAction, targets: [FileItem]) -> some View {
        let isApplicable = actionApplies(action: action, targets: targets)
        let toolReady = isToolAvailable(action: action)
        let canRun = isApplicable && toolReady

        return Button {
            if canRun {
                appState.runAction(action)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.systemImage)
                    .font(.title3)
                    .foregroundStyle(canRun ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(canRun ? .primary : .secondary)

                    if !action.subtitle.isEmpty {
                        Text(action.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !toolReady, let tool = action.requiredTool {
                    Text("Requires \(tool.executableName)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if !isApplicable {
                    Text("Incompatible selection")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
    }

    private func filteredActions(allActions: [ConversionAction], mode: ActionRingMode, targets: [FileItem]) -> [ConversionAction] {
        allActions.filter { action in
            guard action.ringMode == mode else { return false }
            if !searchText.isEmpty {
                let matchesTitle = action.title.localizedCaseInsensitiveContains(searchText)
                let matchesSubtitle = action.subtitle.localizedCaseInsensitiveContains(searchText)
                if !matchesTitle && !matchesSubtitle { return false }
            }
            return true
        }
    }

    private func actionApplies(action: ConversionAction, targets: [FileItem]) -> Bool {
        guard !targets.isEmpty else { return false }
        let kinds = Set(targets.map(\.type.kind))
        guard action.applicableKinds.isSuperset(of: kinds) else { return false }
        guard targets.count >= action.minSelection else { return false }
        if let max = action.maxSelection, targets.count > max { return false }
        return true
    }

    private func isToolAvailable(action: ConversionAction) -> Bool {
        guard let tool = action.requiredTool else { return true }
        return appState.toolStatuses[tool]?.isUsable == true
    }

    private func targetSummary(_ targets: [FileItem]) -> String {
        let isSelection = !appState.selectedItems.isEmpty
        let prefix = isSelection ? "Selected \(targets.count)" : "All \(targets.count)"
        let kinds = Dictionary(grouping: targets, by: { $0.type.kind.rawValue.capitalized })
            .map { "\($0.value.count) \($0.key.lowercased())\($0.value.count > 1 ? "s" : "")" }
            .joined(separator: ", ")
        return "\(prefix) file(s): \(kinds)"
    }
}
