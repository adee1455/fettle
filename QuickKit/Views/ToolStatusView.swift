import AppKit
import SwiftUI

struct ToolStatusView: View {
    @Environment(AppState.self) private var appState
    @State private var copiedHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External Tools")
                        .font(.title2.weight(.bold))
                    Text("QuickKit detects command-line tools in Homebrew (/opt/homebrew and /usr/local). No external binaries are bundled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Refresh") {
                    appState.refreshTools()
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(KnownTool.allCases, id: \.self) { tool in
                    toolCard(tool)
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private func toolCard(_ tool: KnownTool) -> some View {
        let status = appState.toolStatuses[tool] ?? .missing
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tool.executableName)
                    .font(.headline)

                Spacer()

                statusPill(status)
            }

            Text(status.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !status.isUsable {
                Divider()

                HStack {
                    Text(tool.installHint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tool.installHint, forType: .string)
                        copiedHint = tool.executableName
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            if copiedHint == tool.executableName {
                                copiedHint = nil
                            }
                        }
                    } label: {
                        Text(copiedHint == tool.executableName ? "Copied" : "Copy Command")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func statusPill(_ status: ToolStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .available:
                return ("Ready", .green)
            case .incompatibleArchitecture:
                return ("Wrong Arch", .orange)
            case .missing:
                return ("Missing", .secondary)
            }
        }()

        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
