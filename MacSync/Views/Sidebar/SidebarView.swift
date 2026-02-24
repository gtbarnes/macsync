import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    @State private var profilesExpanded = true
    @State private var activeTasksExpanded = true
    @State private var historyExpanded = true

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            // MARK: - Profiles
            Section(isExpanded: $profilesExpanded) {
                ForEach(appState.profiles) { profile in
                    ProfileRow(profile: profile)
                        .tag(AppState.SidebarSelection.profile(profile.id))
                        .contextMenu {
                            Button("Edit") {
                                appState.editingProfile = profile
                                appState.showEditProfileSheet = true
                            }
                            Button("Duplicate") {
                                appState.duplicateProfile(profile)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                appState.deleteProfile(profile)
                            }
                        }
                }
            } header: {
                Label("Profiles", systemImage: "folder.badge.gearshape")
            }

            // MARK: - Active Tasks
            Section(isExpanded: $activeTasksExpanded) {
                ForEach(appState.activeTasks) { task in
                    ActiveTaskRow(task: task)
                        .tag(AppState.SidebarSelection.activeTask(task.id))
                }
            } header: {
                Label("Active Tasks", systemImage: "bolt.fill")
            }

            // MARK: - History
            Section(isExpanded: $historyExpanded) {
                ForEach(appState.taskHistory) { entry in
                    HistoryRow(entry: entry)
                        .tag(AppState.SidebarSelection.historyEntry(entry.id))
                }
            } header: {
                Label("History", systemImage: "clock")
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let profile: SyncProfile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .lineLimit(1)
                Text(profile.syncMode.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: profile.syncMode.systemImage)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Active Task Row

struct ActiveTaskRow: View {
    @ObservedObject var task: SyncTask

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.profile.name)
                    .lineLimit(1)
                ProgressView(value: task.progress.fractionCompleted)
                    .progressViewStyle(.linear)
                Text(task.phase.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.green)
                .symbolEffect(.pulse, isActive: task.phase.isActive)
        }
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let entry: CompletedTask

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.profileName)
                    .lineLimit(1)
                Text(relativeTime(from: entry.endTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.success ? .green : .red)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
