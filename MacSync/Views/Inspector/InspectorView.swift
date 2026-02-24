import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var appState: AppState

    private var selectedProfile: SyncProfile? {
        appState.selectedProfile
    }

    private var activeTask: SyncTask? {
        if let profile = selectedProfile {
            return appState.activeTask(for: profile.id)
        }
        return appState.selectedTask
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let task = activeTask, task.phase.isActive || task.phase == .previewing || task.phase == .paused || task.phase == .completed || task.phase == .failed {
                    taskStatusSection(task)
                    diagnosticsSection(task)
                    if let error = task.errorMessage {
                        errorSection(error)
                    }
                } else if let profile = selectedProfile {
                    profileInfoSection(profile)
                } else {
                    emptyState
                }
            }
            .padding()
        }
    }

    // MARK: - Profile Info Section

    @ViewBuilder
    private func profileInfoSection(_ profile: SyncProfile) -> some View {
        GroupBox("Profile Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Mode") {
                    Label(profile.syncMode.displayName, systemImage: profile.syncMode.systemImage)
                }
                LabeledContent("Threads") {
                    Text("\(profile.threadCount)")
                        .monospacedDigit()
                }
                LabeledContent("Deletion") {
                    Text(profile.deletionPolicy.displayName)
                }
                Divider()
                LabeledContent("Source") {
                    Text(profile.sourcePath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .font(.caption)
                }
                LabeledContent("Destination") {
                    Text(profile.destinationPath)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Task Status Section

    @ViewBuilder
    private func taskStatusSection(_ task: SyncTask) -> some View {
        GroupBox("Task Status") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Phase") {
                    Text(task.phase.displayName)
                        .foregroundStyle(task.phase == .failed ? .red : .primary)
                }
                LabeledContent("Mode") {
                    Label(task.profile.syncMode.displayName, systemImage: task.profile.syncMode.systemImage)
                }
                LabeledContent("Threads") {
                    Text("\(task.profile.threadCount)")
                        .monospacedDigit()
                }
                if task.phase == .syncing {
                    Divider()
                    LabeledContent("Speed") {
                        Text(task.progress.speedFormatted)
                            .monospacedDigit()
                    }
                    LabeledContent("ETA") {
                        Text(task.progress.etaFormatted)
                            .monospacedDigit()
                    }
                    LabeledContent("Files") {
                        Text("\(task.progress.completedFiles) / \(task.progress.totalFiles)")
                            .monospacedDigit()
                    }
                    LabeledContent("Transferred") {
                        Text(ByteCountFormatter.string(fromByteCount: task.progress.transferredBytes, countStyle: .file))
                            .monospacedDigit()
                    }
                    ProgressView(value: task.progress.fractionCompleted)
                        .progressViewStyle(.linear)
                }
            }
        }
    }

    // MARK: - Diagnostics Section

    @ViewBuilder
    private func diagnosticsSection(_ task: SyncTask) -> some View {
        GroupBox("Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Bottleneck") {
                    Text(task.diagnostics.bottleneck.displayName)
                        .foregroundColor(task.diagnostics.bottleneck == .none ? .secondary : .orange)
                }
                LabeledContent("Disk Read") {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(task.diagnostics.diskReadSpeed), countStyle: .file) + "/s")
                        .monospacedDigit()
                }
                LabeledContent("Network") {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(task.diagnostics.networkSpeed), countStyle: .file) + "/s")
                        .monospacedDigit()
                }
                LabeledContent("Active Threads") {
                    Text("\(task.diagnostics.activeThreads)")
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Error Section

    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        GroupBox {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(error)
                    .foregroundStyle(.white)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Error", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        }
        .backgroundStyle(.red.opacity(0.85))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No selection")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }
}
