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
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Comparing files\u{2026}")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
