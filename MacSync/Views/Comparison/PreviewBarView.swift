import SwiftUI

struct PreviewBarView: View {
    @EnvironmentObject var appState: AppState
    let actions: [FileAction]
    let task: SyncTask?

    private var copyCount: Int {
        actions.filter { $0.action == .copyRight || $0.action == .copyLeft }.count
    }

    private var deleteCount: Int {
        actions.filter { $0.action == .deleteSource || $0.action == .deleteDest }.count
    }

    private var totalBytes: Int64 {
        actions.compactMap { $0.sourceSize ?? $0.destSize }.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Summary counts
            HStack(spacing: 12) {
                Label("\(copyCount) copies", systemImage: "doc.on.doc")
                    .foregroundStyle(.green)
                Label("\(deleteCount) deletions", systemImage: "trash")
                    .foregroundStyle(.red)
                Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Spacer()

            // Action buttons based on state
            if let task = task, task.phase == .syncing {
                // Syncing state: progress + speed + ETA
                HStack(spacing: 8) {
                    ProgressView(value: task.progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text(task.progress.speedFormatted)
                        .font(.caption)
                        .monospacedDigit()
                    Text("ETA: \(task.progress.etaFormatted)")
                        .font(.caption)
                        .monospacedDigit()
                }
            } else if !actions.isEmpty {
                // Preview ready: Start Sync + Cancel
                Button("Start Sync") {
                    appState.startSelectedTask()
                }
                .controlSize(.small)

                Button("Cancel") {
                    appState.stopSelectedTask()
                }
                .controlSize(.small)
            } else {
                // Idle: Compare button
                Button("Compare") {
                    appState.startSelectedTask()
                }
                .controlSize(.small)
                .disabled(appState.selectedProfile == nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
