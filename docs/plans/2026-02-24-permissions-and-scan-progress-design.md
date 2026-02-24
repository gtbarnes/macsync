# Permissions Prompts & Comparison Scan Progress

**Date:** 2026-02-24
**Status:** Approved

## Problem

1. MacSync is non-sandboxed (`ENABLE_APP_SANDBOX: NO`), but macOS still requires the user to manually grant Full Disk Access via System Settings. The app has no code that checks for this or guides the user, so comparisons silently fail on protected directories.

2. The comparison scan shows only a generic spinner ("Comparing files…") with no indication of progress or what's being scanned.

## Design

### 1. System Permissions

#### Full Disk Access Check

- **On first launch:** Attempt to read a protected test path (`~/Library/Mail`). If access is denied, present a modal welcome dialog explaining that Full Disk Access is required, with a "Open System Settings" button that navigates to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
- **Before each comparison:** Quick access check on source and destination paths. If either fails with a permission error, show an alert naming the inaccessible path with a "Grant Access" button opening System Settings.
- **Track first-launch state** via `UserDefaults` key `hasCheckedFullDiskAccess`.

#### Notifications Permission

- Request `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])` on first launch so the app can notify when a long-running sync completes in the background.

#### No Other Permissions Needed

Camera, microphone, contacts, location, etc. are not used.

### 2. Comparison Scan Progress

Replace the generic "Comparing files…" spinner in `ComparisonView.comparingState` with a live-updating display:

- **Indeterminate progress bar** — `ProgressView()` linear style, since rsync dry-run doesn't report total file count upfront.
- **File counter** — "4,827 files scanned" ticking up in real-time. Sourced from `task.previewResults.count`, which already updates live via the `AsyncThrowingStream`.
- **Current file path** — single-line truncated text showing the `relativePath` of the most recently parsed `FileAction`. Add a `@Published var lastScannedPath: String?` to `SyncTask` and update it in `TaskCoordinator.compareTask()` as results stream in.

Layout:
```
    ━━━━━━━━━━━ (indeterminate progress bar) ━━━━━━━━━━━
              4,827 files scanned
    /Photos/2024/vacation/IMG_4291.jpg
```

## Files Affected

| File | Changes |
|------|---------|
| `MacSync/Resources/MacSync.entitlements` | (no changes needed — already non-sandboxed) |
| `project.yml` | (no changes needed) |
| **New:** `MacSync/Services/PermissionService.swift` | Full Disk Access check, System Settings URL opener, notifications permission request |
| `MacSync/App/MacSyncApp.swift` | Call `PermissionService` checks on `.onAppear` |
| `MacSync/App/AppState.swift` | Wire permission alerts |
| `MacSync/Models/SyncTask.swift` | Add `@Published var lastScannedPath: String?` |
| `MacSync/Engine/TaskCoordinator.swift` | Update `lastScannedPath` during comparison stream, add pre-comparison permission check |
| `MacSync/Views/Comparison/ComparisonView.swift` | Replace `comparingState` with live counter + file path display |
