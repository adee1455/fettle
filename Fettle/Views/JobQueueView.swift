import SwiftUI

struct JobQueueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let jobManager = appState.jobManager

        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        Text("Conversion Jobs")
                            .font(.title2.weight(.bold))
                    }

                    Text(summaryText(jobs: jobManager.jobs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    jobManager.clearFinished()
                } label: {
                    Label("Clear Finished", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!jobManager.jobs.contains(where: { isFinished($0) }))
            }
            .padding(.horizontal, 4)

            if jobManager.jobs.isEmpty {
                ContentUnavailableView(
                    "No Active Conversions",
                    systemImage: "checklist",
                    description: Text("Select files in Finder and hold Shift, or drop files here to start converting.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(jobManager.jobs) { job in
                        jobCard(job)
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(18)
    }

    private func jobCard(_ job: Job) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Action Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusColor(job.status).opacity(0.14))
                    .frame(width: 40, height: 40)

                Image(systemName: job.action.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusColor(job.status))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(job.action.title)
                        .font(.system(size: 14, weight: .semibold))

                    statusBadge(job.status)

                    Spacer()

                    if job.status == .queued || job.status == .running {
                        Button {
                            appState.jobManager.cancel(job)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel job")
                    } else {
                        Button {
                            appState.jobManager.removeJob(job)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from queue")
                    }
                }

                Text(inputFilesDescription(job.inputFiles))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if job.status == .running {
                    ProgressView(value: job.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .padding(.vertical, 2)
                }

                HStack(spacing: 8) {
                    Text(job.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(job.status == .failed ? .red : .secondary)

                    if let error = job.errorMessage {
                        Text("• \(error)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !job.outputURLs.isEmpty {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(job.outputURLs)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("Show in Finder")
                            }
                            .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if job.status == .running {
                        Text("\(Int(job.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusBadge(_ status: JobStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .queued: ("Queued", .blue)
            case .running: ("Running", .green)
            case .completed: ("Completed", .primary)
            case .failed: ("Failed", .red)
            case .cancelled: ("Cancelled", .orange)
            }
        }()

        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .queued: .blue
        case .running: .green
        case .completed: .accentColor
        case .failed: .red
        case .cancelled: .orange
        }
    }

    private func isFinished(_ job: Job) -> Bool {
        job.status == .completed || job.status == .failed || job.status == .cancelled
    }

    private func summaryText(jobs: [Job]) -> String {
        let running = jobs.filter { $0.status == .running }.count
        let queued = jobs.filter { $0.status == .queued }.count
        let completed = jobs.filter { $0.status == .completed }.count
        let failed = jobs.filter { $0.status == .failed }.count
        return "\(running) running · \(queued) queued · \(completed) completed\(failed > 0 ? " · \(failed) failed" : "")"
    }

    private func inputFilesDescription(_ files: [FileItem]) -> String {
        if files.count == 1 {
            return files[0].displayName
        }
        return "\(files.count) files: \(files.prefix(3).map(\.displayName).joined(separator: ", "))\(files.count > 3 ? "…" : "")"
    }
}
