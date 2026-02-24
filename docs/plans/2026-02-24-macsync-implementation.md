# MacSync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS file synchronization app using rsync 3.x as the backend, with a three-pane SwiftUI UI, parallel execution, network share auto-reconnect, and multi-task support.

**Architecture:** rsync Process Manager — the app spawns rsync child processes via Foundation `Process`, splits directory trees for parallelism, and monitors network mounts for auto-reconnect. UI follows the AI Photo Library's `NavigationSplitView` + `AppState` pattern.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit NSTableView (wrapped), Foundation Process, Swift Concurrency, NetFS framework, Security framework (Keychain), GRDB (SQLite), rsync 3.2.x (bundled)

**Reference project:** AI Photo Library at `/Volumes/Storage VIII/Programming/AiPhotoLibrary/` — follow its patterns for App entry point, AppState, NavigationSplitView layout, toolbar, and inspector.

**Git/Deploy:** Push every commit to `gtbarnes/macsync` on GitHub. After every successful build, deploy via `scp -r /path/to/MacSync.app gary@Garys-Laptop.local:~/Applications/`.

---

## Phase 1: Project Scaffold & Data Model

### Task 1: Create Xcode project

**Files:**
- Create: `MacSync.xcodeproj` (via Xcode CLI or manually)
- Create: `MacSync/App/MacSyncApp.swift`
- Create: `MacSync/App/ContentView.swift`
- Create: `MacSync/Info.plist` (non-sandboxed)
- Create: `.gitignore`

**Step 1: Create the Xcode project**

Use `xcodebuild` or create manually. The project should be:
- macOS App target
- SwiftUI lifecycle
- Bundle identifier: `com.macsync.app`
- Deployment target: macOS 14.0+
- **Non-sandboxed** (remove sandbox entitlement)
- App name: "MacSync"

Project directory structure (matching AI Photo Library):
```
MacSync/
├── MacSync.xcodeproj/
├── MacSync/
│   ├── App/
│   │   ├── MacSyncApp.swift
│   │   ├── AppState.swift
│   │   └── ContentView.swift
│   ├── Models/
│   ├── Views/
│   │   ├── Sidebar/
│   │   ├── Comparison/
│   │   ├── Inspector/
│   │   └── Settings/
│   ├── Engine/
│   ├── Services/
│   └── Resources/
│       └── rsync  (bundled binary, added later)
├── MacSyncTests/
├── docs/
└── .gitignore
```

**Step 2: Create the App entry point**

`MacSync/App/MacSyncApp.swift` — modeled after AI Photo Library's `AiPhotoLibraryApp.swift`:

```swift
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MacSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("MacSync") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appState.initialize()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sync Profile...") {
                    appState.showNewProfileSheet = true
                }
                .keyboardShortcut("n")
            }
            CommandMenu("View") {
                Button("Toggle Inspector") {
                    appState.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
```

**Step 3: Create a minimal ContentView**

`MacSync/App/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            ComparisonView()
                .toolbar {
                    toolbarContent
                }
                .inspector(isPresented: $appState.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { appState.showNewProfileSheet = true } label: {
                Label("New Task", systemImage: "plus")
            }

            Button { appState.startSelectedTask() } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(appState.selectedProfile == nil)

            Button { appState.pauseSelectedTask() } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(appState.activeTask(for: appState.selectedProfile?.id) == nil)

            Button { appState.stopSelectedTask() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(appState.activeTask(for: appState.selectedProfile?.id) == nil)
        }

        ToolbarItem(placement: .automatic) {
            HStack(spacing: 4) {
                Text("Threads:")
                    .font(.caption)
                Stepper(value: $appState.globalThreadLimit, in: 1...32) {
                    Text("\(appState.globalThreadLimit)")
                        .monospacedDigit()
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                appState.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }
}
```

**Step 4: Create stub views**

Create placeholder files that compile:
- `MacSync/Views/Sidebar/SidebarView.swift`
- `MacSync/Views/Comparison/ComparisonView.swift`
- `MacSync/Views/Inspector/InspectorView.swift`
- `MacSync/Views/Settings/SettingsView.swift`

Each is a simple `struct XView: View { var body: some View { Text("X") } }` with `@EnvironmentObject var appState: AppState`.

**Step 5: Build and verify it compiles**

Run: `xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold Xcode project with three-pane NavigationSplitView layout"
git push origin main
```

---

### Task 2: Define all model types

**Files:**
- Create: `MacSync/Models/SyncProfile.swift`
- Create: `MacSync/Models/SyncTask.swift`
- Create: `MacSync/Models/FileAction.swift`
- Create: `MacSync/Models/SyncProgress.swift`
- Create: `MacSync/Models/FilterConfig.swift`

**Step 1: Create SyncProfile model**

`MacSync/Models/SyncProfile.swift`:

```swift
import Foundation

enum SyncMode: String, Codable, CaseIterable, Identifiable {
    case synchronize  // Bidirectional
    case mirror       // One-way with deletes
    case update       // One-way, no deletes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .synchronize: return "Synchronize"
        case .mirror: return "Mirror"
        case .update: return "Update"
        }
    }

    var description: String {
        switch self {
        case .synchronize: return "Two-way: both sides match, newest wins conflicts"
        case .mirror: return "One-way: destination becomes exact copy of source (deletes included)"
        case .update: return "One-way: copy newer files only, never delete"
        }
    }

    var systemImage: String {
        switch self {
        case .synchronize: return "arrow.left.arrow.right"
        case .mirror: return "arrow.right.square"
        case .update: return "arrow.right"
        }
    }
}

enum DeletionPolicy: Codable, Hashable {
    case trash
    case versioning(path: String)
    case permanent

    var displayName: String {
        switch self {
        case .trash: return "Move to Trash"
        case .versioning: return "Versioning Folder"
        case .permanent: return "Permanent Delete"
        }
    }
}

struct NetworkShareConfig: Codable, Hashable {
    var serverURL: String      // e.g. "smb://nas.local/share"
    var keychainAccount: String // Keychain lookup key for credentials
    var autoReconnect: Bool
    var maxReconnectAttempts: Int
}

struct SyncProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sourcePath: String
    var destinationPath: String
    var syncMode: SyncMode
    var deletionPolicy: DeletionPolicy
    var threadCount: Int
    var filters: FilterConfig
    var rsyncExtraFlags: [String]
    var networkShareConfig: NetworkShareConfig?
    var createdAt: Date
    var lastSyncedAt: Date?

    init(
        name: String,
        sourcePath: String,
        destinationPath: String,
        syncMode: SyncMode = .mirror,
        deletionPolicy: DeletionPolicy = .trash,
        threadCount: Int = 4
    ) {
        self.id = UUID()
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.syncMode = syncMode
        self.deletionPolicy = deletionPolicy
        self.threadCount = threadCount
        self.filters = FilterConfig()
        self.rsyncExtraFlags = []
        self.networkShareConfig = nil
        self.createdAt = Date()
        self.lastSyncedAt = nil
    }
}
```

**Step 2: Create FilterConfig**

`MacSync/Models/FilterConfig.swift`:

```swift
import Foundation

struct FilterConfig: Codable, Hashable {
    var includePatterns: [String]   // e.g. ["*.jpg", "*.png"]
    var excludePatterns: [String]   // e.g. [".DS_Store", "Thumbs.db", ".macsync_partial/"]

    init() {
        self.includePatterns = []
        self.excludePatterns = [".DS_Store", "Thumbs.db", ".macsync_partial/", "._*"]
    }

    var rsyncFlags: [String] {
        var flags: [String] = []
        for pattern in includePatterns {
            flags += ["--include", pattern]
        }
        for pattern in excludePatterns {
            flags += ["--exclude", pattern]
        }
        return flags
    }
}
```

**Step 3: Create FileAction model**

`MacSync/Models/FileAction.swift`:

```swift
import Foundation

enum ActionType: String, CaseIterable {
    case copyRight     // Source → Destination
    case copyLeft      // Destination → Source (synchronize mode only)
    case equal         // Identical, no action
    case deleteSource  // Will be deleted from source (synchronize mode)
    case deleteDest    // Will be deleted from destination (mirror mode)
    case conflict      // Both sides changed (synchronize mode)

    var displayName: String {
        switch self {
        case .copyRight: return "Copy →"
        case .copyLeft: return "← Copy"
        case .equal: return "Equal"
        case .deleteSource: return "Delete Source"
        case .deleteDest: return "Delete Dest"
        case .conflict: return "Conflict"
        }
    }

    var systemImage: String {
        switch self {
        case .copyRight: return "arrow.right.circle.fill"
        case .copyLeft: return "arrow.left.circle.fill"
        case .equal: return "checkmark.circle"
        case .deleteSource, .deleteDest: return "trash.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .copyRight, .copyLeft: return "green"
        case .equal: return "gray"
        case .deleteSource, .deleteDest: return "red"
        case .conflict: return "orange"
        }
    }
}

struct FileAction: Identifiable {
    let id: UUID
    let relativePath: String
    let action: ActionType
    let sourceSize: Int64?
    let destSize: Int64?
    let sourceModified: Date?
    let destModified: Date?
    var excluded: Bool

    init(relativePath: String, action: ActionType,
         sourceSize: Int64? = nil, destSize: Int64? = nil,
         sourceModified: Date? = nil, destModified: Date? = nil) {
        self.id = UUID()
        self.relativePath = relativePath
        self.action = action
        self.sourceSize = sourceSize
        self.destSize = destSize
        self.sourceModified = sourceModified
        self.destModified = destModified
        self.excluded = false
    }

    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    var directory: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}
```

**Step 4: Create SyncProgress and SyncTask**

`MacSync/Models/SyncProgress.swift`:

```swift
import Foundation

struct SyncProgress {
    var totalFiles: Int = 0
    var completedFiles: Int = 0
    var totalBytes: Int64 = 0
    var transferredBytes: Int64 = 0
    var currentSpeed: Double = 0        // bytes per second
    var smoothedSpeed: Double = 0       // exponentially smoothed
    var startTime: Date?
    var currentFile: String = ""

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    var eta: TimeInterval? {
        guard smoothedSpeed > 0 else { return nil }
        let remaining = Double(totalBytes - transferredBytes)
        return remaining / smoothedSpeed
    }

    var etaFormatted: String {
        guard let eta = eta else { return "--:--" }
        let hours = Int(eta) / 3600
        let minutes = (Int(eta) % 3600) / 60
        let seconds = Int(eta) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var speedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(smoothedSpeed), countStyle: .file) + "/s"
    }
}

enum TaskPhase: String {
    case idle
    case comparing
    case previewing
    case syncing
    case paused
    case completed
    case failed

    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .comparing: return "Comparing…"
        case .previewing: return "Preview Ready"
        case .syncing: return "Syncing…"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var isActive: Bool {
        self == .comparing || self == .syncing
    }
}

enum Bottleneck: String {
    case none
    case disk
    case network
    case cpu

    var displayName: String {
        switch self {
        case .none: return "None"
        case .disk: return "Disk I/O"
        case .network: return "Network"
        case .cpu: return "CPU"
        }
    }
}

struct DiagnosticState {
    var bottleneck: Bottleneck = .none
    var diskReadSpeed: Double = 0     // bytes/s
    var diskWriteSpeed: Double = 0
    var networkSpeed: Double = 0
    var activeThreads: Int = 0
}
```

`MacSync/Models/SyncTask.swift`:

```swift
import Foundation
import Combine

@MainActor
class SyncTask: ObservableObject, Identifiable {
    let id: UUID
    let profile: SyncProfile
    @Published var phase: TaskPhase = .idle
    @Published var previewResults: [FileAction] = []
    @Published var progress: SyncProgress = SyncProgress()
    @Published var errorMessage: String?
    @Published var diagnostics: DiagnosticState = DiagnosticState()

    var rsyncProcesses: [Process] = []
    var isCancelled: Bool = false

    init(profile: SyncProfile) {
        self.id = UUID()
        self.profile = profile
    }
}
```

**Step 5: Build and verify**

Run: `xcodebuild -project MacSync.xcodeproj -scheme MacSync build`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add MacSync/Models/
git commit -m "feat: define all data models — SyncProfile, SyncTask, FileAction, SyncProgress"
git push origin main
```

---

### Task 3: Create AppState

**Files:**
- Create: `MacSync/App/AppState.swift`

**Step 1: Write AppState**

`MacSync/App/AppState.swift` — modeled after AI Photo Library's AppState with @Published properties:

```swift
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - View State
    @Published var showInspector: Bool = false
    @Published var showNewProfileSheet: Bool = false
    @Published var showEditProfileSheet: Bool = false
    @Published var showSettingsSheet: Bool = false

    // MARK: - Sidebar Selection
    enum SidebarSelection: Hashable {
        case profile(UUID)
        case activeTask(UUID)
        case historyEntry(UUID)
    }
    @Published var sidebarSelection: SidebarSelection?

    // MARK: - Profiles
    @Published var profiles: [SyncProfile] = []

    // MARK: - Active Tasks
    @Published var activeTasks: [SyncTask] = []

    // MARK: - History
    @Published var taskHistory: [CompletedTask] = []

    // MARK: - Global Settings
    @Published var globalThreadLimit: Int = 4

    // MARK: - Services
    var profileStore: ProfileStore?
    var taskCoordinator: TaskCoordinator?
    // var historyStore: HistoryStore?  // Added in Phase 8

    // MARK: - Computed Properties

    var selectedProfile: SyncProfile? {
        guard case .profile(let id) = sidebarSelection else { return nil }
        return profiles.first { $0.id == id }
    }

    var selectedTask: SyncTask? {
        guard case .activeTask(let id) = sidebarSelection else { return nil }
        return activeTasks.first { $0.id == id }
    }

    // MARK: - Initialization

    func initialize() {
        let store = ProfileStore()
        self.profileStore = store
        self.profiles = store.loadProfiles()
        self.taskCoordinator = TaskCoordinator(appState: self)

        // Restore global settings
        let savedThreads = UserDefaults.standard.integer(forKey: "globalThreadLimit")
        if savedThreads > 0 { globalThreadLimit = savedThreads }
        let savedInspector = UserDefaults.standard.bool(forKey: "showInspector")
        showInspector = savedInspector
    }

    // MARK: - Profile Actions

    func saveProfile(_ profile: SyncProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profileStore?.saveProfiles(profiles)
    }

    func deleteProfile(_ profile: SyncProfile) {
        profiles.removeAll { $0.id == profile.id }
        profileStore?.saveProfiles(profiles)
    }

    // MARK: - Task Actions

    func startSelectedTask() {
        guard let profile = selectedProfile else { return }
        taskCoordinator?.startTask(for: profile)
    }

    func pauseSelectedTask() {
        guard case .activeTask(let id) = sidebarSelection else { return }
        taskCoordinator?.pauseTask(id: id)
    }

    func stopSelectedTask() {
        guard case .activeTask(let id) = sidebarSelection else { return }
        taskCoordinator?.stopTask(id: id)
    }

    func activeTask(for profileID: UUID?) -> SyncTask? {
        guard let profileID else { return nil }
        return activeTasks.first { $0.profile.id == profileID }
    }

    // MARK: - Settings Persistence

    func saveSettings() {
        UserDefaults.standard.set(globalThreadLimit, forKey: "globalThreadLimit")
        UserDefaults.standard.set(showInspector, forKey: "showInspector")
    }
}

// Placeholder for history
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
```

**Step 2: Build and verify**

Run: `xcodebuild build`
Expected: BUILD SUCCEEDED (some services won't exist yet — use stubs or conditional compilation)

**Step 3: Commit**

```bash
git add MacSync/App/AppState.swift
git commit -m "feat: add AppState with profile management, task coordination, settings"
git push origin main
```

---

## Phase 2: Profile Persistence & Management

### Task 4: Create ProfileStore

**Files:**
- Create: `MacSync/Services/ProfileStore.swift`

**Step 1: Implement ProfileStore**

`MacSync/Services/ProfileStore.swift`:

```swift
import Foundation

class ProfileStore {
    private let profilesDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        profilesDirectory = appSupport.appendingPathComponent("MacSync/Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    func loadProfiles() -> [SyncProfile] {
        let url = profilesDirectory.appendingPathComponent("profiles.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SyncProfile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [SyncProfile]) {
        let url = profilesDirectory.appendingPathComponent("profiles.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Services/ProfileStore.swift
git commit -m "feat: add ProfileStore for JSON-based profile persistence"
git push origin main
```

---

### Task 5: Create Profile Editor Sheet

**Files:**
- Create: `MacSync/Views/ProfileEditor/ProfileEditorView.swift`

**Step 1: Implement profile editor**

`MacSync/Views/ProfileEditor/ProfileEditorView.swift`:

```swift
import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var sourcePath: String
    @State private var destinationPath: String
    @State private var syncMode: SyncMode
    @State private var deletionPolicy: DeletionPolicy
    @State private var threadCount: Int
    @State private var excludePatterns: String

    let existingProfile: SyncProfile?

    init(profile: SyncProfile? = nil) {
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _sourcePath = State(initialValue: profile?.sourcePath ?? "")
        _destinationPath = State(initialValue: profile?.destinationPath ?? "")
        _syncMode = State(initialValue: profile?.syncMode ?? .mirror)
        _deletionPolicy = State(initialValue: profile?.deletionPolicy ?? .trash)
        _threadCount = State(initialValue: profile?.threadCount ?? 4)
        _excludePatterns = State(initialValue: profile?.filters.excludePatterns.joined(separator: "\n") ?? FilterConfig().excludePatterns.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
            }

            Section("Paths") {
                HStack {
                    TextField("Source", text: $sourcePath)
                    Button("Browse…") { browseSource() }
                }
                HStack {
                    TextField("Destination", text: $destinationPath)
                    Button("Browse…") { browseDestination() }
                }
            }

            Section("Sync Mode") {
                Picker("Mode", selection: $syncMode) {
                    ForEach(SyncMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(syncMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Deletion Policy") {
                Picker("When files are deleted", selection: $deletionPolicy) {
                    Text("Move to Trash").tag(DeletionPolicy.trash)
                    Text("Permanent Delete").tag(DeletionPolicy.permanent)
                }
                // Versioning folder option with path picker can be added later
            }

            Section("Performance") {
                Stepper("Threads: \(threadCount)", value: $threadCount, in: 1...32)
            }

            Section("Exclude Patterns") {
                TextEditor(text: $excludePatterns)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                Text("One pattern per line. e.g. .DS_Store, *.tmp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isEmpty || sourcePath.isEmpty || destinationPath.isEmpty)
            }
        }
    }

    private func browseSource() {
        if let url = browseFolder(title: "Select Source Directory") {
            sourcePath = url.path
        }
    }

    private func browseDestination() {
        if let url = browseFolder(title: "Select Destination Directory") {
            destinationPath = url.path
        }
    }

    private func browseFolder(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = title
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func save() {
        var profile = existingProfile ?? SyncProfile(
            name: name,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            syncMode: syncMode,
            deletionPolicy: deletionPolicy,
            threadCount: threadCount
        )

        if existingProfile != nil {
            profile.name = name
            profile.sourcePath = sourcePath
            profile.destinationPath = destinationPath
            profile.syncMode = syncMode
            profile.deletionPolicy = deletionPolicy
            profile.threadCount = threadCount
        }

        profile.filters = FilterConfig()
        profile.filters.excludePatterns = excludePatterns
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        appState.saveProfile(profile)
        dismiss()
    }
}
```

**Step 2: Wire up the sheet in ContentView**

Add `.sheet(isPresented: $appState.showNewProfileSheet)` to ContentView's detail view.

**Step 3: Build, verify, commit**

```bash
git add MacSync/Views/ProfileEditor/
git commit -m "feat: add ProfileEditorView with mode, paths, filters, thread config"
git push origin main
```

---

## Phase 3: Sidebar & UI Shell

### Task 6: Build SidebarView

**Files:**
- Modify: `MacSync/Views/Sidebar/SidebarView.swift`

**Step 1: Implement the three-section sidebar**

Modeled after AI Photo Library's `SidebarView.swift` with collapsible sections:

```swift
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var profilesExpanded = true
    @State private var activeExpanded = true
    @State private var historyExpanded = true

    var body: some View {
        List(selection: $appState.sidebarSelection) {
            // MARK: - Profiles Section
            Section(isExpanded: $profilesExpanded) {
                ForEach(appState.profiles) { profile in
                    ProfileRow(profile: profile)
                        .tag(AppState.SidebarSelection.profile(profile.id))
                        .contextMenu {
                            Button("Edit…") {
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
                Label("Profiles", systemImage: "folder")
            }

            // MARK: - Active Tasks Section
            Section(isExpanded: $activeExpanded) {
                ForEach(appState.activeTasks) { task in
                    ActiveTaskRow(task: task)
                        .tag(AppState.SidebarSelection.activeTask(task.id))
                }
            } header: {
                Label("Active", systemImage: "arrow.triangle.2.circlepath")
            }

            // MARK: - History Section
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

// MARK: - Row Views

struct ProfileRow: View {
    let profile: SyncProfile

    var body: some View {
        HStack {
            Image(systemName: profile.syncMode.systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .lineLimit(1)
                Text(profile.sourcePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct ActiveTaskRow: View {
    @ObservedObject var task: SyncTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                Text(task.profile.name)
                    .lineLimit(1)
            }
            ProgressView(value: task.progress.fractionCompleted)
                .progressViewStyle(.linear)
            Text(task.phase.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct HistoryRow: View {
    let entry: CompletedTask

    var body: some View {
        HStack {
            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.success ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.profileName)
                    .lineLimit(1)
                Text(entry.endTime, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Views/Sidebar/
git commit -m "feat: build SidebarView with profiles, active tasks, history sections"
git push origin main
```

---

### Task 7: Build ComparisonView (main content area)

**Files:**
- Modify: `MacSync/Views/Comparison/ComparisonView.swift`
- Create: `MacSync/Views/Comparison/ComparisonTableView.swift` (AppKit NSTableView wrapped)
- Create: `MacSync/Views/Comparison/PreviewBarView.swift`

**Step 1: Create the main ComparisonView**

This shows either a "select a profile" empty state, or the two-panel comparison view with preview bar:

```swift
import SwiftUI

struct ComparisonView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let profile = appState.selectedProfile {
            VStack(spacing: 0) {
                // Path header
                PathHeaderView(profile: profile)

                Divider()

                // Comparison table (bulk of the view)
                if let task = appState.activeTask(for: profile.id),
                   !task.previewResults.isEmpty {
                    ComparisonTableRepresentable(actions: task.previewResults)
                } else {
                    emptyComparisonView(profile: profile)
                }

                Divider()

                // Preview summary bar
                if let task = appState.activeTask(for: profile.id) {
                    PreviewBarView(task: task)
                }
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Select a profile to begin")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func emptyComparisonView(profile: SyncProfile) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Click Compare to preview changes")
                .foregroundStyle(.secondary)
            Button("Compare") {
                appState.taskCoordinator?.compareTask(for: profile)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PathHeaderView: View {
    let profile: SyncProfile

    var body: some View {
        HStack(spacing: 0) {
            // Source
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(profile.sourcePath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 30)

            // Destination
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.green)
                Text(profile.destinationPath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }
}
```

**Step 2: Create PreviewBarView**

`MacSync/Views/Comparison/PreviewBarView.swift`:

```swift
import SwiftUI

struct PreviewBarView: View {
    @ObservedObject var task: SyncTask
    @EnvironmentObject var appState: AppState

    private var copyCount: Int {
        task.previewResults.filter { !$0.excluded && ($0.action == .copyRight || $0.action == .copyLeft) }.count
    }

    private var deleteCount: Int {
        task.previewResults.filter { !$0.excluded && ($0.action == .deleteSource || $0.action == .deleteDest) }.count
    }

    private var totalBytes: Int64 {
        task.previewResults
            .filter { !$0.excluded && $0.action != .equal }
            .compactMap { $0.sourceSize }
            .reduce(0, +)
    }

    var body: some View {
        HStack {
            // Summary
            HStack(spacing: 16) {
                Label("\(copyCount) copy", systemImage: "doc.on.doc")
                    .foregroundStyle(.green)
                Label("\(deleteCount) delete", systemImage: "trash")
                    .foregroundStyle(.red)
                Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            Spacer()

            // Actions
            if task.phase == .previewing {
                Button("Cancel") {
                    appState.stopSelectedTask()
                }

                Button("Start Sync") {
                    appState.taskCoordinator?.executeSyncTask(task)
                }
                .buttonStyle(.borderedProminent)
            } else if task.phase == .syncing {
                ProgressView(value: task.progress.fractionCompleted)
                    .frame(width: 120)
                Text(task.progress.speedFormatted)
                    .font(.caption)
                    .monospacedDigit()
                Text("ETA: \(task.progress.etaFormatted)")
                    .font(.caption)
                    .monospacedDigit()
            } else if task.phase == .comparing {
                ProgressView()
                    .controlSize(.small)
                Text("Comparing…")
                    .font(.callout)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
```

**Step 3: Create NSTableView wrapper for comparison table**

`MacSync/Views/Comparison/ComparisonTableRepresentable.swift` — wraps AppKit `NSTableView` for performance with 100k+ rows (matching AI Photo Library's `PhotoGridRepresentable` pattern):

```swift
import SwiftUI
import AppKit

struct ComparisonTableRepresentable: NSViewRepresentable {
    let actions: [FileAction]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        // Columns
        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = ""
        actionCol.width = 30
        actionCol.minWidth = 30
        actionCol.maxWidth = 30
        tableView.addTableColumn(actionCol)

        let sourceCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceCol.title = "Source"
        sourceCol.width = 300
        sourceCol.minWidth = 100
        tableView.addTableColumn(sourceCol)

        let arrowCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("arrow"))
        arrowCol.title = ""
        arrowCol.width = 40
        arrowCol.minWidth = 40
        arrowCol.maxWidth = 40
        tableView.addTableColumn(arrowCol)

        let destCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dest"))
        destCol.title = "Destination"
        destCol.width = 300
        destCol.minWidth = 100
        tableView.addTableColumn(destCol)

        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "Size"
        sizeCol.width = 80
        sizeCol.minWidth = 60
        tableView.addTableColumn(sizeCol)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .inset
        tableView.rowHeight = 22

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        context.coordinator.tableView = tableView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.actions = actions
        context.coordinator.tableView?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var actions: [FileAction]
        weak var tableView: NSTableView?

        init(actions: [FileAction]) {
            self.actions = actions
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            actions.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < actions.count else { return nil }
            let action = actions[row]
            let identifier = tableColumn?.identifier.rawValue ?? ""

            let cell = NSTextField(labelWithString: "")
            cell.lineBreakMode = .byTruncatingMiddle

            switch identifier {
            case "action":
                let imageView = NSImageView()
                imageView.image = NSImage(systemSymbolName: action.excluded ? "circle" : action.action.systemImage, accessibilityDescription: nil)
                imageView.contentTintColor = action.excluded ? .tertiaryLabelColor : colorForAction(action.action)
                return imageView
            case "source":
                cell.stringValue = action.relativePath
                cell.textColor = action.excluded ? .tertiaryLabelColor : .labelColor
            case "arrow":
                cell.stringValue = arrowForAction(action.action)
                cell.alignment = .center
                cell.textColor = action.excluded ? .tertiaryLabelColor : colorForAction(action.action)
            case "dest":
                cell.stringValue = action.relativePath
                cell.textColor = action.excluded ? .tertiaryLabelColor : .labelColor
            case "size":
                if let size = action.sourceSize {
                    cell.stringValue = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                }
                cell.alignment = .right
                cell.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            default:
                break
            }

            return cell
        }

        private func arrowForAction(_ action: ActionType) -> String {
            switch action {
            case .copyRight: return "►"
            case .copyLeft: return "◄"
            case .equal: return "="
            case .deleteSource: return "✕"
            case .deleteDest: return "✕"
            case .conflict: return "⚠"
            }
        }

        private func colorForAction(_ action: ActionType) -> NSColor {
            switch action {
            case .copyRight, .copyLeft: return .systemGreen
            case .equal: return .tertiaryLabelColor
            case .deleteSource, .deleteDest: return .systemRed
            case .conflict: return .systemOrange
            }
        }
    }
}
```

**Step 4: Build, verify, commit**

```bash
git add MacSync/Views/Comparison/
git commit -m "feat: build ComparisonView with NSTableView wrapper and preview bar"
git push origin main
```

---

### Task 8: Build InspectorView

**Files:**
- Modify: `MacSync/Views/Inspector/InspectorView.swift`

**Step 1: Implement inspector with task status and diagnostics**

```swift
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let task = currentTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    taskStatusSection(task)
                    Divider()
                    diagnosticsSection(task)
                }
                .padding()
            }
        } else if let profile = appState.selectedProfile {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileInfoSection(profile)
                }
                .padding()
            }
        } else {
            Text("No selection")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentTask: SyncTask? {
        if case .activeTask(let id) = appState.sidebarSelection {
            return appState.activeTasks.first { $0.id == id }
        }
        if let profile = appState.selectedProfile {
            return appState.activeTask(for: profile.id)
        }
        return nil
    }

    // MARK: - Sections

    private func profileInfoSection(_ profile: SyncProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile Info")
                .font(.headline)
            LabeledContent("Mode", value: profile.syncMode.displayName)
            LabeledContent("Threads", value: "\(profile.threadCount)")
            LabeledContent("Deletion", value: profile.deletionPolicy.displayName)
            LabeledContent("Source", value: profile.sourcePath)
            LabeledContent("Destination", value: profile.destinationPath)
        }
    }

    private func taskStatusSection(_ task: SyncTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Status")
                .font(.headline)
            LabeledContent("Phase", value: task.phase.displayName)
            LabeledContent("Mode", value: task.profile.syncMode.displayName)
            LabeledContent("Threads", value: "\(task.profile.threadCount)")

            if task.phase == .syncing {
                Divider()
                LabeledContent("Speed", value: task.progress.speedFormatted)
                LabeledContent("ETA", value: task.progress.etaFormatted)
                LabeledContent("Files") {
                    Text("\(task.progress.completedFiles) / \(task.progress.totalFiles)")
                        .monospacedDigit()
                }
                LabeledContent("Transferred") {
                    Text(ByteCountFormatter.string(fromByteCount: task.progress.transferredBytes, countStyle: .file))
                        .monospacedDigit()
                }
                ProgressView(value: task.progress.fractionCompleted)
            }

            if let error = task.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.red.opacity(0.1)))
            }
        }
    }

    private func diagnosticsSection(_ task: SyncTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.headline)
            LabeledContent("Bottleneck", value: task.diagnostics.bottleneck.displayName)
            LabeledContent("Disk Read") {
                Text(ByteCountFormatter.string(fromByteCount: Int64(task.diagnostics.diskReadSpeed), countStyle: .file) + "/s")
                    .monospacedDigit()
            }
            LabeledContent("Network") {
                Text(ByteCountFormatter.string(fromByteCount: Int64(task.diagnostics.networkSpeed), countStyle: .file) + "/s")
                    .monospacedDigit()
            }
            LabeledContent("Active Threads", value: "\(task.diagnostics.activeThreads)")
        }
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Views/Inspector/
git commit -m "feat: build InspectorView with task status and diagnostics sections"
git push origin main
```

---

## Phase 4: rsync Engine

### Task 9: Bundle rsync 3.x binary

**Files:**
- Add: `MacSync/Resources/rsync` (binary)
- Create: `MacSync/Engine/RsyncBinary.swift` (locator)

**Step 1: Install and locate rsync 3.x**

```bash
# Install via Homebrew if not present
brew install rsync
# Find the binary
which rsync  # should be /opt/homebrew/bin/rsync or /usr/local/bin/rsync
rsync --version  # verify it's 3.2.x+
```

**Step 2: Create binary locator**

`MacSync/Engine/RsyncBinary.swift`:

```swift
import Foundation

enum RsyncBinary {
    /// Returns the path to the rsync binary.
    /// Prefers the bundled binary, falls back to Homebrew, then system.
    static var path: String {
        // 1. Bundled in app resources
        if let bundled = Bundle.main.path(forResource: "rsync", ofType: nil) {
            return bundled
        }
        // 2. Homebrew (Apple Silicon)
        let homebrew = "/opt/homebrew/bin/rsync"
        if FileManager.default.isExecutableFile(atPath: homebrew) {
            return homebrew
        }
        // 3. Homebrew (Intel)
        let homebrewIntel = "/usr/local/bin/rsync"
        if FileManager.default.isExecutableFile(atPath: homebrewIntel) {
            return homebrewIntel
        }
        // 4. System fallback (old 2.6.9)
        return "/usr/bin/rsync"
    }

    static var version: String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: "\n").first ?? "unknown"
    }
}
```

**Step 3: Copy rsync binary into Resources**

Add a build phase in Xcode to copy the Homebrew rsync binary into the app bundle, OR copy it manually:
```bash
cp $(which rsync) MacSync/Resources/rsync
chmod +x MacSync/Resources/rsync
```

Also ensure the binary is added to the Xcode project's "Copy Bundle Resources" build phase.

**Step 4: Commit**

```bash
git add MacSync/Engine/RsyncBinary.swift MacSync/Resources/rsync
git commit -m "feat: add rsync 3.x binary locator and bundled binary"
git push origin main
```

---

### Task 10: Build RsyncCommandBuilder

**Files:**
- Create: `MacSync/Engine/RsyncCommandBuilder.swift`

**Step 1: Implement command builder**

`MacSync/Engine/RsyncCommandBuilder.swift`:

```swift
import Foundation

struct RsyncCommand {
    let executablePath: String
    let arguments: [String]
    let sourcePath: String
    let destinationPath: String

    var fullCommand: String {
        ([executablePath] + arguments + [sourcePath, destinationPath]).joined(separator: " ")
    }
}

class RsyncCommandBuilder {
    private let profile: SyncProfile
    private let partialDir = ".macsync_partial"

    init(profile: SyncProfile) {
        self.profile = profile
    }

    /// Build command for dry-run preview
    func buildPreviewCommand() -> RsyncCommand {
        var args = baseFlags()
        args += ["--dry-run", "--itemize-changes"]
        args += modeFlags()
        args += filterFlags()
        args += profile.rsyncExtraFlags

        return RsyncCommand(
            executablePath: RsyncBinary.path,
            arguments: args,
            sourcePath: ensureTrailingSlash(profile.sourcePath),
            destinationPath: ensureTrailingSlash(profile.destinationPath)
        )
    }

    /// Build command for actual sync execution
    func buildSyncCommand() -> RsyncCommand {
        var args = baseFlags()
        args += ["--partial-dir=\(partialDir)", "--info=progress2"]
        args += modeFlags()
        args += deletionFlags()
        args += filterFlags()
        args += profile.rsyncExtraFlags

        return RsyncCommand(
            executablePath: RsyncBinary.path,
            arguments: args,
            sourcePath: ensureTrailingSlash(profile.sourcePath),
            destinationPath: ensureTrailingSlash(profile.destinationPath)
        )
    }

    /// Build command for a specific subtree (parallel execution)
    func buildSyncCommand(filesFrom tempFilePath: String) -> RsyncCommand {
        var args = baseFlags()
        args += ["--partial-dir=\(partialDir)", "--info=progress2"]
        args += ["--files-from=\(tempFilePath)"]
        args += modeFlags()
        args += deletionFlags()
        args += filterFlags()
        args += profile.rsyncExtraFlags

        return RsyncCommand(
            executablePath: RsyncBinary.path,
            arguments: args,
            sourcePath: ensureTrailingSlash(profile.sourcePath),
            destinationPath: ensureTrailingSlash(profile.destinationPath)
        )
    }

    // MARK: - Private

    private func baseFlags() -> [String] {
        ["-avz", "--human-readable"]
    }

    private func modeFlags() -> [String] {
        switch profile.syncMode {
        case .mirror:
            return ["--delete", "--delete-during"]
        case .update:
            return ["--update"]
        case .synchronize:
            // Synchronize is handled by running two passes in RsyncEngine
            return []
        }
    }

    private func deletionFlags() -> [String] {
        guard profile.syncMode == .mirror else { return [] }
        switch profile.deletionPolicy {
        case .trash:
            // rsync doesn't support Trash directly — handled post-sync by moving
            // Use --backup and --backup-dir to a temp location, then move to Trash
            let backupDir = NSTemporaryDirectory() + "macsync_trash_\(UUID().uuidString)"
            return ["--backup", "--backup-dir=\(backupDir)"]
        case .versioning(let path):
            return ["--backup", "--backup-dir=\(path)"]
        case .permanent:
            return []  // --delete already handles it
        }
    }

    private func filterFlags() -> [String] {
        profile.filters.rsyncFlags
    }

    private func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Engine/RsyncCommandBuilder.swift
git commit -m "feat: add RsyncCommandBuilder for preview, sync, and parallel commands"
git push origin main
```

---

### Task 11: Build RsyncOutputParser

**Files:**
- Create: `MacSync/Engine/RsyncOutputParser.swift`

**Step 1: Implement parser for itemized changes and progress**

`MacSync/Engine/RsyncOutputParser.swift`:

```swift
import Foundation

class RsyncOutputParser {

    /// Parse --itemize-changes output into FileAction array.
    /// Format: YXcstpoguax path/to/file
    /// Y = update type: < (sent), > (received), c (local change), h (hard link), . (not updated), * (message)
    /// X = file type: f (file), d (directory), L (symlink), D (device), S (special)
    func parseItemizedChanges(_ output: String, syncMode: SyncMode) -> [FileAction] {
        var actions: [FileAction] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 11 else { continue }

            let flagsEnd = trimmed.index(trimmed.startIndex, offsetBy: 11)
            let flags = String(trimmed[..<flagsEnd])
            let path = String(trimmed[flagsEnd...]).trimmingCharacters(in: .whitespaces)

            guard !path.isEmpty else { continue }

            if let action = parseFlags(flags, path: path, syncMode: syncMode) {
                actions.append(action)
            }
        }

        return actions
    }

    /// Parse --info=progress2 output line.
    /// Format: 1,234,567  45%  12.34MB/s  0:01:23 (xfr#123, to-chk=456/789)
    func parseProgress(_ line: String) -> (bytesTransferred: Int64, percentage: Double, speed: Double, eta: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Match the progress2 format
        let pattern = #"([\d,]+)\s+(\d+)%\s+([\d.]+\w+/s)\s+([\d:]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return nil
        }

        let bytesStr = String(trimmed[Range(match.range(at: 1), in: trimmed)!]).replacingOccurrences(of: ",", with: "")
        let pctStr = String(trimmed[Range(match.range(at: 2), in: trimmed)!])
        let speedStr = String(trimmed[Range(match.range(at: 3), in: trimmed)!])
        let etaStr = String(trimmed[Range(match.range(at: 4), in: trimmed)!])

        let bytes = Int64(bytesStr) ?? 0
        let pct = Double(pctStr) ?? 0
        let speed = parseSpeed(speedStr)

        return (bytes, pct / 100.0, speed, etaStr)
    }

    /// Parse *deleting lines from --itemize-changes
    func parseDeletion(_ line: String) -> FileAction? {
        guard line.hasPrefix("*deleting") else { return nil }
        let path = String(line.dropFirst("*deleting".count)).trimmingCharacters(in: .whitespaces)
        return FileAction(relativePath: path, action: .deleteDest)
    }

    // MARK: - Private

    private func parseFlags(_ flags: String, path: String, syncMode: SyncMode) -> FileAction? {
        guard flags.count >= 11 else { return nil }

        let chars = Array(flags)
        let updateType = chars[0]

        switch updateType {
        case "<":
            // File being sent (source → dest)
            return FileAction(relativePath: path, action: .copyRight)
        case ">":
            // File being received (dest → source) — only in synchronize mode
            return FileAction(relativePath: path, action: .copyLeft)
        case ".":
            // Not being updated (but may have attribute changes)
            let attribs = String(chars[2..<11])
            if attribs.allSatisfy({ $0 == "." || $0 == " " }) {
                return FileAction(relativePath: path, action: .equal)
            }
            return FileAction(relativePath: path, action: .copyRight) // attribute update
        case "*":
            // Message line (e.g., *deleting)
            if flags.hasPrefix("*deleting") {
                return FileAction(relativePath: path, action: .deleteDest)
            }
            return nil
        case "c":
            // Local change (created)
            return FileAction(relativePath: path, action: .copyRight)
        default:
            return nil
        }
    }

    private func parseSpeed(_ str: String) -> Double {
        // Parse "12.34MB/s" or "1.23kB/s" etc.
        let lower = str.lowercased()
        let numStr = lower.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let num = Double(numStr) else { return 0 }

        if lower.contains("gb") { return num * 1_073_741_824 }
        if lower.contains("mb") { return num * 1_048_576 }
        if lower.contains("kb") { return num * 1_024 }
        return num
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Engine/RsyncOutputParser.swift
git commit -m "feat: add RsyncOutputParser for itemized changes and progress2 format"
git push origin main
```

---

### Task 12: Build RsyncEngine

**Files:**
- Create: `MacSync/Engine/RsyncEngine.swift`

**Step 1: Implement the core engine that runs rsync processes**

`MacSync/Engine/RsyncEngine.swift`:

```swift
import Foundation

actor RsyncEngine {
    private let parser = RsyncOutputParser()

    /// Run a preview (dry-run) and return the list of file actions.
    func preview(profile: SyncProfile) -> AsyncThrowingStream<[FileAction], Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                let builder = RsyncCommandBuilder(profile: profile)
                let command = builder.buildPreviewCommand()

                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executablePath)
                process.arguments = command.arguments + [command.sourcePath, command.destinationPath]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                var allActions: [FileAction] = []
                var buffer = ""

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    buffer += String(data: data, encoding: .utf8) ?? ""

                    // Process complete lines
                    while let newlineRange = buffer.range(of: "\n") {
                        let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                        buffer = String(buffer[newlineRange.upperBound...])

                        let newActions = self.parser.parseItemizedChanges(line, syncMode: profile.syncMode)
                        if !newActions.isEmpty {
                            allActions.append(contentsOf: newActions)
                            continuation.yield(allActions)
                        }
                    }
                }

                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    if proc.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "rsync failed with code \(proc.terminationStatus)"
                        continuation.finish(throwing: RsyncError.processError(errMsg))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Execute the actual sync. Returns progress updates.
    func sync(
        profile: SyncProfile,
        onProgress: @escaping (SyncProgress) -> Void
    ) async throws -> [Process] {
        let builder = RsyncCommandBuilder(profile: profile)

        if profile.threadCount <= 1 {
            // Single-threaded: one rsync process
            let command = builder.buildSyncCommand()
            let process = try await runRsyncProcess(command: command, onProgress: onProgress)
            return [process]
        } else {
            // Multi-threaded: split by top-level directories
            let entries = try topLevelEntries(at: profile.sourcePath)
            let chunks = distributeEntries(entries, across: profile.threadCount)
            var processes: [Process] = []

            try await withThrowingTaskGroup(of: Process.self) { group in
                for chunk in chunks {
                    group.addTask {
                        let tempFile = self.writeFilesFromList(chunk)
                        let command = builder.buildSyncCommand(filesFrom: tempFile)
                        return try await self.runRsyncProcess(command: command, onProgress: onProgress)
                    }
                }
                for try await process in group {
                    processes.append(process)
                }
            }

            return processes
        }
    }

    // MARK: - Private

    private func runRsyncProcess(
        command: RsyncCommand,
        onProgress: @escaping (SyncProgress) -> Void
    ) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments + [command.sourcePath, command.destinationPath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var progress = SyncProgress()
        progress.startTime = Date()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

            if let parsed = self.parser.parseProgress(line) {
                progress.transferredBytes = parsed.bytesTransferred
                progress.currentSpeed = parsed.speed
                // Exponential moving average for smoothed speed
                if progress.smoothedSpeed == 0 {
                    progress.smoothedSpeed = parsed.speed
                } else {
                    progress.smoothedSpeed = 0.8 * progress.smoothedSpeed + 0.2 * parsed.speed
                }
                onProgress(progress)
            }
        }

        try process.run()
        return process
    }

    private func topLevelEntries(at path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { !$0.hasPrefix(".") }
    }

    private func distributeEntries(_ entries: [String], across threadCount: Int) -> [[String]] {
        let count = max(1, threadCount)
        var chunks: [[String]] = Array(repeating: [], count: count)
        for (i, entry) in entries.enumerated() {
            chunks[i % count].append(entry)
        }
        return chunks.filter { !$0.isEmpty }
    }

    private func writeFilesFromList(_ entries: [String]) -> String {
        let tempFile = NSTemporaryDirectory() + "macsync_filelist_\(UUID().uuidString).txt"
        let content = entries.joined(separator: "\n")
        try? content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        return tempFile
    }
}

enum RsyncError: LocalizedError {
    case processError(String)
    case networkDisconnected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processError(let msg): return msg
        case .networkDisconnected: return "Network share disconnected"
        case .cancelled: return "Sync cancelled"
        }
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Engine/RsyncEngine.swift
git commit -m "feat: add RsyncEngine with preview, sync, parallel execution via TaskGroup"
git push origin main
```

---

## Phase 5: Task Coordination

### Task 13: Build TaskCoordinator

**Files:**
- Create: `MacSync/Engine/TaskCoordinator.swift`

**Step 1: Implement TaskCoordinator**

`MacSync/Engine/TaskCoordinator.swift`:

```swift
import Foundation

@MainActor
class TaskCoordinator {
    private weak var appState: AppState?
    private let rsyncEngine = RsyncEngine()

    init(appState: AppState) {
        self.appState = appState
    }

    /// Run preview comparison for a profile
    func compareTask(for profile: SyncProfile) {
        guard let appState else { return }

        let task = SyncTask(profile: profile)
        task.phase = .comparing
        appState.activeTasks.append(task)
        appState.sidebarSelection = .activeTask(task.id)

        Task {
            do {
                for try await actions in await rsyncEngine.preview(profile: profile) {
                    task.previewResults = actions
                }
                task.phase = .previewing
            } catch {
                task.phase = .failed
                task.errorMessage = error.localizedDescription
            }
        }
    }

    /// Execute sync after preview
    func executeSyncTask(_ task: SyncTask) {
        task.phase = .syncing
        task.progress = SyncProgress()
        task.progress.totalFiles = task.previewResults.filter { !$0.excluded && $0.action != .equal }.count
        task.progress.totalBytes = task.previewResults
            .filter { !$0.excluded && $0.action != .equal }
            .compactMap { $0.sourceSize }
            .reduce(0, +)

        Task {
            do {
                let processes = try await rsyncEngine.sync(profile: task.profile) { progress in
                    Task { @MainActor in
                        task.progress.transferredBytes = progress.transferredBytes
                        task.progress.currentSpeed = progress.currentSpeed
                        task.progress.smoothedSpeed = progress.smoothedSpeed
                    }
                }
                task.rsyncProcesses = processes

                // Wait for all processes to finish
                await withTaskGroup(of: Void.self) { group in
                    for process in processes {
                        group.addTask {
                            process.waitUntilExit()
                        }
                    }
                }

                // Check results
                let allSucceeded = processes.allSatisfy { $0.terminationStatus == 0 }
                task.phase = allSucceeded ? .completed : .failed

                if !allSucceeded {
                    task.errorMessage = "One or more rsync processes failed"
                }

                // Record in history
                self.recordHistory(task: task)
            } catch {
                task.phase = .failed
                task.errorMessage = error.localizedDescription
            }
        }
    }

    func pauseTask(id: UUID) {
        guard let task = appState?.activeTasks.first(where: { $0.id == id }) else { return }
        for process in task.rsyncProcesses where process.isRunning {
            process.suspend()  // SIGSTOP
        }
        task.phase = .paused
    }

    func resumeTask(id: UUID) {
        guard let task = appState?.activeTasks.first(where: { $0.id == id }) else { return }
        for process in task.rsyncProcesses {
            process.resume()  // SIGCONT
        }
        task.phase = .syncing
    }

    func stopTask(id: UUID) {
        guard let task = appState?.activeTasks.first(where: { $0.id == id }) else { return }
        task.isCancelled = true
        for process in task.rsyncProcesses where process.isRunning {
            process.terminate()
        }
        task.phase = .failed
        task.errorMessage = "Cancelled by user"
        recordHistory(task: task)
    }

    private func recordHistory(task: SyncTask) {
        let entry = CompletedTask(
            id: UUID(),
            profileName: task.profile.name,
            syncMode: task.profile.syncMode,
            startTime: task.progress.startTime ?? Date(),
            endTime: Date(),
            filesTransferred: task.progress.completedFiles,
            bytesTransferred: task.progress.transferredBytes,
            errors: task.phase == .failed ? 1 : 0,
            success: task.phase == .completed
        )
        appState?.taskHistory.insert(entry, at: 0)
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Engine/TaskCoordinator.swift
git commit -m "feat: add TaskCoordinator for compare, sync, pause, resume, stop"
git push origin main
```

---

## Phase 6: Network Share Monitor

### Task 14: Build NetworkShareMonitor

**Files:**
- Create: `MacSync/Services/NetworkShareMonitor.swift`
- Create: `MacSync/Services/KeychainService.swift`

**Step 1: Create KeychainService**

`MacSync/Services/KeychainService.swift`:

```swift
import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    func save(account: String, server: String, password: String) throws {
        let data = password.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: account,
            kSecAttrServer as String: server,
            kSecAttrLabel as String: "MacSync: \(server)",
            kSecValueData as String: data
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(account: String, server: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: account,
            kSecAttrServer as String: server,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String, server: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: account,
            kSecAttrServer as String: server
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        var errorDescription: String? {
            "Keychain save failed with status \(self)"
        }
    }
}
```

**Step 2: Create NetworkShareMonitor**

`MacSync/Services/NetworkShareMonitor.swift`:

```swift
import Foundation
import NetFS

class NetworkShareMonitor {
    private let mountPath: String
    private let shareURL: String
    private let keychainAccount: String
    private let maxAttempts: Int

    private var pollTimer: DispatchSourceTimer?
    private var isReconnecting = false
    private var reconnectAttempt = 0

    var onDisconnected: (() -> Void)?
    var onReconnected: (() -> Void)?
    var onReconnectFailed: ((String) -> Void)?

    init(mountPath: String, config: NetworkShareConfig) {
        self.mountPath = mountPath
        self.shareURL = config.serverURL
        self.keychainAccount = config.keychainAccount
        self.maxAttempts = config.maxReconnectAttempts
    }

    func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.checkMount()
        }
        timer.resume()
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func checkMount() {
        var statInfo = stat()
        let result = stat(mountPath, &statInfo)

        if result != 0 {
            // Mount point not accessible — disconnected
            if !isReconnecting {
                isReconnecting = true
                reconnectAttempt = 0
                onDisconnected?()
                attemptReconnect()
            }
        } else if isReconnecting {
            // Was reconnecting but mount is back
            isReconnecting = false
            reconnectAttempt = 0
            onReconnected?()
        }
    }

    private func attemptReconnect() {
        guard reconnectAttempt < maxAttempts else {
            onReconnectFailed?("Failed after \(maxAttempts) attempts")
            return
        }

        reconnectAttempt += 1

        // Exponential backoff: 5s, 10s, 20s, 40s... max 120s
        let delay = min(5.0 * pow(2.0, Double(reconnectAttempt - 1)), 120.0)

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.mountShare()
        }
    }

    private func mountShare() {
        guard let url = URL(string: shareURL) as CFURL? else {
            onReconnectFailed?("Invalid share URL: \(shareURL)")
            return
        }

        // Get credentials from Keychain
        let server = URL(string: shareURL)?.host ?? ""
        let password = KeychainService.shared.retrieve(account: keychainAccount, server: server)

        var requestID: AsyncRequestID?

        NetFSMountURLAsync(
            url,
            nil,                          // mount path (nil = auto)
            keychainAccount as CFString,   // username
            (password ?? "") as CFString,  // password
            nil,                          // open options
            nil,                          // mount options
            &requestID,
            DispatchQueue.global()
        ) { [weak self] status, requestID, mountpoints in
            if status == 0 {
                // Success — the poll timer will detect the mount is back
            } else {
                // Failed — retry
                self?.attemptReconnect()
            }
        }
    }
}
```

**Step 3: Build, verify, commit**

```bash
git add MacSync/Services/NetworkShareMonitor.swift MacSync/Services/KeychainService.swift
git commit -m "feat: add NetworkShareMonitor with SMB auto-reconnect and Keychain credential storage"
git push origin main
```

---

## Phase 7: Settings & Polish

### Task 15: Build SettingsView

**Files:**
- Modify: `MacSync/Views/Settings/SettingsView.swift`

**Step 1: Implement settings**

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("globalThreadLimit") var threadLimit: Int = 4
    @AppStorage("showInspector") var showInspector: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            rsyncTab
                .tabItem { Label("rsync", systemImage: "terminal") }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section("Performance") {
                Stepper("Default Thread Count: \(threadLimit)", value: $threadLimit, in: 1...32)
                Text("Number of parallel rsync processes per sync task")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show Inspector by Default", isOn: $showInspector)
            }
        }
        .formStyle(.grouped)
    }

    private var rsyncTab: some View {
        Form {
            Section("rsync Binary") {
                LabeledContent("Path", value: RsyncBinary.path)
                LabeledContent("Version", value: RsyncBinary.version)
            }
        }
        .formStyle(.grouped)
    }
}
```

**Step 2: Build, verify, commit**

```bash
git add MacSync/Views/Settings/
git commit -m "feat: add SettingsView with thread count and rsync info"
git push origin main
```

---

### Task 16: Wire up all views and complete the app shell

**Files:**
- Modify: `MacSync/App/ContentView.swift` — add sheet modifiers
- Modify: `MacSync/App/MacSyncApp.swift` — finalize commands

**Step 1: Add sheet and overlay modifiers to ContentView**

Ensure ContentView includes:
- `.sheet(isPresented: $appState.showNewProfileSheet)` → `ProfileEditorView()`
- `.sheet(isPresented: $appState.showEditProfileSheet)` → `ProfileEditorView(profile: appState.editingProfile)`

**Step 2: Build the full app and verify**

Run: `xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Release build`
Expected: BUILD SUCCEEDED

**Step 3: Commit and deploy**

```bash
git add -A
git commit -m "feat: wire up all views, complete app shell with profiles, comparison, inspector"
git push origin main
# Deploy to laptop
scp -r "$(xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Release -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')/MacSync.app" gary@Garys-Laptop.local:~/Applications/
```

---

## Phase 8: History & Database

### Task 17: Add GRDB for history persistence

**Files:**
- Create: `MacSync/Database/HistoryStore.swift`
- Add: GRDB package dependency

**Step 1: Add GRDB via Swift Package Manager**

In Xcode: File → Add Package Dependencies → `https://github.com/groue/GRDB.swift`

**Step 2: Implement HistoryStore**

`MacSync/Database/HistoryStore.swift`:

```swift
import Foundation
import GRDB

class HistoryStore {
    private var dbQueue: DatabaseQueue?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MacSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("history.db").path

        do {
            dbQueue = try DatabaseQueue(path: dbPath)
            try migrate()
        } catch {
            print("Failed to open history database: \(error)")
        }
    }

    private func migrate() throws {
        try dbQueue?.write { db in
            try db.create(table: "completed_tasks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("profileName", .text).notNull()
                t.column("syncMode", .text).notNull()
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime).notNull()
                t.column("filesTransferred", .integer).notNull()
                t.column("bytesTransferred", .integer).notNull()
                t.column("errors", .integer).notNull()
                t.column("success", .boolean).notNull()
            }
        }
    }

    func save(_ task: CompletedTask) {
        try? dbQueue?.write { db in
            try db.execute(
                sql: """
                INSERT INTO completed_tasks (id, profileName, syncMode, startTime, endTime,
                    filesTransferred, bytesTransferred, errors, success)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    task.id.uuidString, task.profileName, task.syncMode.rawValue,
                    task.startTime, task.endTime, task.filesTransferred,
                    task.bytesTransferred, task.errors, task.success
                ]
            )
        }
    }

    func loadHistory(limit: Int = 100) -> [CompletedTask] {
        (try? dbQueue?.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM completed_tasks ORDER BY endTime DESC LIMIT ?
            """, arguments: [limit])
                .map { row in
                    CompletedTask(
                        id: UUID(uuidString: row["id"]) ?? UUID(),
                        profileName: row["profileName"],
                        syncMode: SyncMode(rawValue: row["syncMode"]) ?? .mirror,
                        startTime: row["startTime"],
                        endTime: row["endTime"],
                        filesTransferred: row["filesTransferred"],
                        bytesTransferred: row["bytesTransferred"],
                        errors: row["errors"],
                        success: row["success"]
                    )
                }
        }) ?? []
    }

    func clearHistory() {
        try? dbQueue?.write { db in
            try db.execute(sql: "DELETE FROM completed_tasks")
        }
    }
}
```

**Step 3: Wire into AppState**

Add `historyStore` property to AppState, load history in `initialize()`, save in TaskCoordinator's `recordHistory()`.

**Step 4: Build, verify, commit**

```bash
git add MacSync/Database/ Package.swift
git commit -m "feat: add GRDB-backed HistoryStore for sync history persistence"
git push origin main
```

---

## Phase 9: Build & Deploy Automation

### Task 18: Create build and deploy script

**Files:**
- Create: `scripts/build-and-deploy.sh`

**Step 1: Write the script**

`scripts/build-and-deploy.sh`:

```bash
#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacSync"
SCHEME="MacSync"
CONFIG="Release"
LAPTOP="gary@Garys-Laptop.local"
LAPTOP_PATH="~/Applications"

echo "=== Building $APP_NAME ==="
cd "$PROJECT_DIR"

xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath build/ \
    build

BUILD_DIR="build/Build/Products/$CONFIG"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build product not found at $APP_PATH"
    exit 1
fi

echo "=== Build Succeeded ==="

echo "=== Deploying to laptop ==="
scp -r "$APP_PATH" "$LAPTOP:$LAPTOP_PATH/"
echo "=== Deployed to $LAPTOP:$LAPTOP_PATH/$APP_NAME.app ==="

echo "=== Pushing to GitHub ==="
git push origin main 2>/dev/null || echo "(push skipped or failed)"

echo "=== Done ==="
```

**Step 2: Make executable and commit**

```bash
chmod +x scripts/build-and-deploy.sh
git add scripts/
git commit -m "feat: add build-and-deploy script for laptop deployment"
git push origin main
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 1. Scaffold | 1-3 | Xcode project, all models, AppState |
| 2. Profiles | 4-5 | Profile persistence, editor UI |
| 3. UI Shell | 6-8 | Sidebar, comparison view, inspector |
| 4. rsync Engine | 9-12 | Bundled rsync, command builder, parser, engine |
| 5. Coordination | 13 | TaskCoordinator with compare/sync/pause/stop |
| 6. Network | 14 | NetworkShareMonitor, Keychain, auto-reconnect |
| 7. Settings | 15-16 | Settings view, wiring all views together |
| 8. History | 17 | GRDB-backed history persistence |
| 9. Deploy | 18 | Build + deploy script |

**Total: 18 tasks across 9 phases**

Each task is independently buildable and committable. The app is functional after Phase 5 (can compare and sync), with network reconnection added in Phase 6 and polish in Phases 7-9.
