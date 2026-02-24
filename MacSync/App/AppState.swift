import SwiftUI
import Combine

struct CompletedTask: Identifiable, Codable {
    let id: UUID
    let profileName: String
    let syncMode: SyncMode
    let startTime: Date
    let endTime: Date
    let filesTransferred: Int
    let bytesTransferred: Int64
    let errors: Int
    let success: Bool
}

@MainActor
final class AppState: ObservableObject {
    // MARK: - Persistence
    let profileStore = ProfileStore()
    let historyStore = HistoryStore()

    // MARK: - Engine
    var taskCoordinator: TaskCoordinator?

    // MARK: - View State
    @Published var showInspector: Bool = false
    @Published var showNewProfileSheet: Bool = false
    @Published var showEditProfileSheet: Bool = false

    // MARK: - Permission Alerts
    @Published var showFullDiskAccessAlert: Bool = false
    @Published var permissionErrorMessage: String = ""
    @Published var showPathAccessAlert: Bool = false
    @Published var pathAccessAlertMessage: String = ""

    // MARK: - Sidebar Selection
    enum SidebarSelection: Hashable {
        case profile(UUID)
        case activeTask(UUID)
        case historyEntry(UUID)
    }
    @Published var sidebarSelection: SidebarSelection?

    // MARK: - Profiles
    @Published var profiles: [SyncProfile] = []
    @Published var editingProfile: SyncProfile?

    // MARK: - Active Tasks
    @Published var activeTasks: [SyncTask] = []

    // MARK: - History
    @Published var taskHistory: [CompletedTask] = []

    // MARK: - Global Settings
    @Published var globalThreadLimit: Int = 4

    // MARK: - Computed Properties
    var selectedProfile: SyncProfile? {
        guard case .profile(let id) = sidebarSelection else { return nil }
        return profiles.first { $0.id == id }
    }

    var selectedTask: SyncTask? {
        guard case .activeTask(let id) = sidebarSelection else { return nil }
        return activeTasks.first { $0.id == id }
    }

    var selectedTaskIsNotRunning: Bool {
        guard let profile = selectedProfile else { return true }
        return activeTasks.first { $0.profile.id == profile.id && $0.phase.isActive } == nil
    }

    // MARK: - Initialization
    func initialize() {
        let savedThreads = UserDefaults.standard.integer(forKey: "globalThreadLimit")
        if savedThreads > 0 { globalThreadLimit = savedThreads }
        showInspector = UserDefaults.standard.bool(forKey: "showInspector")
        profiles = profileStore.loadProfiles()
        taskHistory = historyStore.loadHistory()
        taskCoordinator = TaskCoordinator(appState: self)
    }

    // MARK: - Permissions
    func checkPermissionsOnLaunch() async {
        // Run blocking I/O off the main thread
        let hasFDA = await Task.detached(priority: .utility) {
            await PermissionService.shared.runFirstLaunchChecks()
        }.value
        if !hasFDA {
            NSApp.activate(ignoringOtherApps: true)
            showFullDiskAccessAlert = true
        }
    }

    // MARK: - Profile Actions
    func saveProfile(_ profile: SyncProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profileStore.saveProfiles(profiles)
    }

    func deleteProfile(_ profile: SyncProfile) {
        profiles.removeAll { $0.id == profile.id }
        profileStore.saveProfiles(profiles)
    }

    func duplicateProfile(_ profile: SyncProfile) {
        var dup = SyncProfile(name: profile.name + " Copy", sourcePath: profile.sourcePath,
                              destinationPath: profile.destinationPath, syncMode: profile.syncMode,
                              deletionPolicy: profile.deletionPolicy, threadCount: profile.threadCount)
        dup.filters = profile.filters
        dup.rsyncExtraFlags = profile.rsyncExtraFlags
        dup.networkShareConfig = profile.networkShareConfig
        profiles.append(dup)
    }

    // MARK: - Task Actions

    func startSelectedTask() {
        // If there's a selected task with preview ready, execute sync
        if let task = selectedTask, task.phase == .previewing {
            taskCoordinator?.executeSyncTask(task)
            return
        }
        // If a profile's task exists and is previewing, execute sync
        if let profile = selectedProfile,
           let task = activeTask(for: profile.id),
           task.phase == .previewing {
            taskCoordinator?.executeSyncTask(task)
            return
        }
        // Otherwise, start comparison for the selected profile
        if let profile = selectedProfile {
            taskCoordinator?.compareTask(for: profile)
        }
    }

    func pauseSelectedTask() {
        if let task = selectedTask {
            if task.phase == .paused {
                taskCoordinator?.resumeTask(id: task.id)
            } else {
                taskCoordinator?.pauseTask(id: task.id)
            }
        } else if let profile = selectedProfile,
                  let task = activeTask(for: profile.id) {
            if task.phase == .paused {
                taskCoordinator?.resumeTask(id: task.id)
            } else {
                taskCoordinator?.pauseTask(id: task.id)
            }
        }
    }

    func stopSelectedTask() {
        if let task = selectedTask {
            taskCoordinator?.stopTask(id: task.id)
        } else if let profile = selectedProfile,
                  let task = activeTask(for: profile.id) {
            taskCoordinator?.stopTask(id: task.id)
        }
    }

    func activeTask(for profileID: UUID?) -> SyncTask? {
        guard let profileID else { return nil }
        return activeTasks.first { $0.profile.id == profileID }
    }
}
