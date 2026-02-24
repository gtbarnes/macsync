# Permissions & Scan Progress Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add system permission prompts (Full Disk Access + Notifications) and live comparison scan progress (file counter + current file path).

**Architecture:** New `PermissionService` singleton handles all permission checks and System Settings deep-links. `SyncTask` gains a `lastScannedPath` property updated during the comparison stream. `ComparisonView.comparingState` is replaced with a live-updating progress display. Permission checks run at app launch and before each comparison.

**Tech Stack:** SwiftUI, UserNotifications framework, Foundation FileManager

---

### Task 1: Create PermissionService

**Files:**
- Create: `MacSync/Services/PermissionService.swift`

**Step 1: Write PermissionService**

```swift
import Foundation
import UserNotifications

@MainActor
final class PermissionService {
    static let shared = PermissionService()
    private init() {}

    // MARK: - Full Disk Access

    /// Tests whether the app has Full Disk Access by probing a protected path.
    func hasFullDiskAccess() -> Bool {
        let testPath = NSHomeDirectory() + "/Library/Mail"
        return FileManager.default.isReadableFile(atPath: testPath)
    }

    /// Checks if a specific path is readable. Returns nil if OK, or an error message.
    func checkPathAccess(_ path: String) -> String? {
        guard !path.isEmpty else { return "Path is empty" }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return "Path does not exist: \(path)"
        }
        guard fm.isReadableFile(atPath: path) else {
            return "Cannot read path (permission denied): \(path)"
        }
        return nil
    }

    /// Opens System Settings → Full Disk Access pane.
    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Notifications

    /// Requests notification authorization. Returns true if granted.
    @discardableResult
    func requestNotificationPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // MARK: - First Launch

    /// Runs first-launch permission checks. Returns true if Full Disk Access is available.
    func runFirstLaunchChecks() async -> Bool {
        let hasChecked = UserDefaults.standard.bool(forKey: "hasCheckedFullDiskAccess")
        let hasFDA = hasFullDiskAccess()

        if !hasChecked {
            UserDefaults.standard.set(true, forKey: "hasCheckedFullDiskAccess")
            await requestNotificationPermission()
        }

        return hasFDA
    }
}
```

**Step 2: Commit**

```bash
git add MacSync/Services/PermissionService.swift
git commit -m "feat: add PermissionService for Full Disk Access and notification checks"
```

---

### Task 2: Wire permission checks into AppState and MacSyncApp

**Files:**
- Modify: `MacSync/App/AppState.swift`
- Modify: `MacSync/App/MacSyncApp.swift`

**Step 1: Add permission alert state to AppState**

In `AppState.swift`, add these published properties after the existing `showEditProfileSheet` line:

```swift
// MARK: - Permission Alerts
@Published var showFullDiskAccessAlert: Bool = false
@Published var permissionErrorMessage: String = ""
```

Add this method after `initialize()`:

```swift
// MARK: - Permissions
func checkPermissionsOnLaunch() async {
    let hasFDA = await PermissionService.shared.runFirstLaunchChecks()
    if !hasFDA {
        showFullDiskAccessAlert = true
    }
}
```

**Step 2: Update MacSyncApp to show permission alert**

In `MacSyncApp.swift`, add a `.task` modifier after `.onAppear` on the ContentView, and an `.alert` modifier:

```swift
ContentView()
    .environmentObject(appState)
    .frame(minWidth: 900, minHeight: 600)
    .onAppear {
        appState.initialize()
    }
    .task {
        await appState.checkPermissionsOnLaunch()
    }
    .alert("Full Disk Access Required", isPresented: $appState.showFullDiskAccessAlert) {
        Button("Open System Settings") {
            PermissionService.shared.openFullDiskAccessSettings()
        }
        Button("Later", role: .cancel) { }
    } message: {
        Text("MacSync needs Full Disk Access to read and sync files across your system. Please enable it in System Settings → Privacy & Security → Full Disk Access.")
    }
```

**Step 3: Build and verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add MacSync/App/AppState.swift MacSync/App/MacSyncApp.swift
git commit -m "feat: wire Full Disk Access alert on first launch"
```

---

### Task 3: Add pre-comparison permission check

**Files:**
- Modify: `MacSync/Engine/TaskCoordinator.swift`
- Modify: `MacSync/App/AppState.swift`

**Step 1: Add path permission alert to AppState**

In `AppState.swift`, add this alert state after the existing permission properties:

```swift
@Published var showPathAccessAlert: Bool = false
@Published var pathAccessAlertMessage: String = ""
```

**Step 2: Add permission check in TaskCoordinator.compareTask**

In `TaskCoordinator.swift`, at the top of `compareTask(for:)`, before the existing duplicate-task check, add:

```swift
// Check path permissions before starting comparison
let permService = PermissionService.shared
if let sourceError = permService.checkPathAccess(profile.sourcePath) {
    appState.pathAccessAlertMessage = sourceError
    appState.showPathAccessAlert = true
    return
}
if let destError = permService.checkPathAccess(profile.destinationPath) {
    appState.pathAccessAlertMessage = destError
    appState.showPathAccessAlert = true
    return
}
```

**Step 3: Add alert in MacSyncApp.swift**

Add another `.alert` modifier after the existing Full Disk Access alert on ContentView:

```swift
.alert("Cannot Access Path", isPresented: $appState.showPathAccessAlert) {
    Button("Open System Settings") {
        PermissionService.shared.openFullDiskAccessSettings()
    }
    Button("OK", role: .cancel) { }
} message: {
    Text(appState.pathAccessAlertMessage)
}
```

**Step 4: Build and verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add MacSync/Engine/TaskCoordinator.swift MacSync/App/AppState.swift MacSync/App/MacSyncApp.swift
git commit -m "feat: add pre-comparison path permission check with alert"
```

---

### Task 4: Add lastScannedPath to SyncTask

**Files:**
- Modify: `MacSync/Models/SyncTask.swift`

**Step 1: Add the property**

In `SyncTask.swift`, add after the `diagnostics` property:

```swift
@Published var lastScannedPath: String?
```

**Step 2: Commit**

```bash
git add MacSync/Models/SyncTask.swift
git commit -m "feat: add lastScannedPath to SyncTask for scan progress display"
```

---

### Task 5: Update TaskCoordinator to track lastScannedPath

**Files:**
- Modify: `MacSync/Engine/TaskCoordinator.swift`

**Step 1: Update the comparison stream loop**

In `TaskCoordinator.compareTask(for:)`, replace the existing stream consumption loop:

```swift
// OLD:
for try await actions in stream {
    guard !task.isCancelled else { break }
    task.previewResults = actions
}
```

With:

```swift
// NEW:
for try await actions in stream {
    guard !task.isCancelled else { break }
    task.previewResults = actions
    task.lastScannedPath = actions.last?.relativePath
}
```

**Step 2: Build and verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacSync/Engine/TaskCoordinator.swift
git commit -m "feat: update lastScannedPath during comparison stream"
```

---

### Task 6: Replace comparingState with live scan progress UI

**Files:**
- Modify: `MacSync/Views/Comparison/ComparisonView.swift`

**Step 1: Replace the comparingState computed property**

Replace the entire `comparingState` property (lines 72-81) with:

```swift
private var comparingState: some View {
    VStack(spacing: 16) {
        Spacer()

        ProgressView()
            .progressViewStyle(.linear)
            .frame(maxWidth: 300)

        if let task = currentTask {
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
        } else {
            Text("Comparing files\u{2026}")
                .font(.title3)
                .foregroundStyle(.secondary)
        }

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

**Step 2: Build and verify**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add MacSync/Views/Comparison/ComparisonView.swift
git commit -m "feat: replace generic spinner with live scan progress counter and file path"
```

---

### Task 7: Final build, deploy, and push

**Files:** None (build/deploy only)

**Step 1: Release build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MacSync.xcodeproj -scheme MacSync -configuration Release -derivedDataPath build/ build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

**Step 2: Deploy locally**

```bash
cp -R build/Build/Products/Release/MacSync.app ~/Applications/
```

**Step 3: Deploy to laptop**

```bash
scp -r build/Build/Products/Release/MacSync.app gary@Garys-Laptop.local:~/Applications/
```

**Step 4: Push to GitHub**

```bash
git push origin main
```
