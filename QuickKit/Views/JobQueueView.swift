import SwiftUI

struct JobQueueView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let jobManager = appState.jobManager

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Job Queue")
                        .font(.title2.weight(.bold))
                    Text(summaryText(jobs: jobManager.jobs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear Finished") {
                    jobManager.clearFinished()
                }
                .disabled(!jobManager.jobs.contains(where: { isFinished($0) }))
            }
            .padding(.horizontal, 4)

            if jobManager.jobs.isEmpty {
                ContentUnavailableView(
                    "No jobs in queue",
                    systemImage: "checklist",
                    description: Text("Select files and run an action from the Action Picker to queue jobs.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(jobManager.jobs) { job in
                        jobRow(job)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
    }

    private func jobRow(_ job: Job) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: job.action.systemImage)
                .font(.title2)
                .foregroundStyle(statusColor(job.status))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.action.title)
                        .font(.headline)

                    statusBadge(job.status)

                    Spacer()

                    if job.status == .queued || job.status == .running {
                        Button {
                            appState.jobManager.cancel(job)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel job")
                    } else {
                        Button {
                            appState.jobManager.removeJob(job)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
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
                }

                HStack {
                    Text(job.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let error = job.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    if !job.outputURLs.isEmpty {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(job.outputURLs)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                Text("Show in Finder")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }

                    if job.status == .running {
                        Text("\(Int(job.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statusBadge(_ status: JobStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .queued: .blue
        case .running: .green
        case .completed: .primary
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
        let finished = jobs.filter { isFinished($0) }.count
        return "\(jobs.count) total · \(running) running · \(queued) queued · \(finished) finished"
    }

    private func inputFilesDescription(_ files: [FileItem]) -> String {
        if files.count == 1 {
            return files[0].displayName
        }
        let names = files.prefix(3).map(\.displayName).joined(separator: ", ")
        if files.count > 3 {
            return "\(names) and \(files.count - 3) more"
        }
        return names
    }
}
