import SwiftUI

struct ComparisonView: View {
    @EnvironmentObject var appState: AppState

    private var currentTask: SyncTask? {
        if let profile = appState.selectedProfile {
            return appState.activeTask(for: profile.id)
        }
        if let task = appState.selectedTask {
            return task
        }
        return nil
    }

    private var actions: [FileAction] {
        currentTask?.previewResults ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if let profile = appState.selectedProfile ?? currentTask?.profile {
                // MARK: - Path Header Bar
                PathHeaderBar(sourcePath: profile.sourcePath, destinationPath: profile.destinationPath)

                // MARK: - Comparison Table or Empty State
                if actions.isEmpty && currentTask?.phase != .comparing {
                    emptyPreviewState
                } else if currentTask?.phase == .comparing {
                    comparingState
                } else {
                    ComparisonTableRepresentable(actions: actions)
                }

                // MARK: - Preview Bar
                Divider()
                PreviewBarView(actions: actions, task: currentTask)
                    .environmentObject(appState)
            } else {
                emptySelectionState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty States

    private var emptySelectionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select a profile to begin")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPreviewState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Click Compare to preview changes")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var comparingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: 300)

            if let task = currentTask {
                if task.previewResults.isEmpty {
                    // Phase 1: rsync is building the file list (no output yet).
                    // For large/network volumes this can take several minutes.
                    Text("Building file list\u{2026}")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if let start = task.comparisonStartTime {
                        ElapsedTimeView(since: start)
                    }

                    Text("Large or network volumes may take several minutes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    // Phase 2: rsync is streaming results
                    Text("\(task.previewResults.count.formatted()) files scanned")
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: task.previewResults.count)

                    if let path = task.lastScannedPath {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 500)
                    }
                }
            } else {
                Text("Comparing files\u{2026}")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Elapsed Time View

/// Displays a live-updating elapsed time since a given start date.
struct ElapsedTimeView: View {
    let since: Date

    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedElapsed)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(since)
            }
            .onAppear {
                elapsed = Date().timeIntervalSince(since)
            }
    }

    private var formattedElapsed: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        if minutes > 0 {
            return "Elapsed: \(minutes)m \(seconds)s"
        } else {
            return "Elapsed: \(seconds)s"
        }
    }
}

// MARK: - Path Header Bar

struct PathHeaderBar: View {
    let sourcePath: String
    let destinationPath: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(sourcePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            Divider()
                .frame(height: 20)

            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.green)
                Text(destinationPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
        .background(.bar)

        Divider()
    }
}
