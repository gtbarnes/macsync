# MacSync — Design Document

**Date:** 2026-02-24
**Status:** Approved

## Overview

MacSync is a macOS file synchronization application — a native alternative to FreeFileSync. It uses rsync 3.x as its backend engine, provides a three-pane SwiftUI interface modeled after the AI Photo Library app, and solves the critical problem of network share disconnection during transfers by automatically reconnecting and resuming.

## Requirements

### Sync Modes
1. **Synchronize** — Bidirectional: both sides end up matching, conflicts resolved by newest modification time
2. **Mirror** — One-way with deletes: destination becomes an exact copy of source, including removing files not present in source
3. **Update** — One-way, no deletes: copy newer/new files from source to destination, never delete anything

### Key Features
- **Preview** before sync: see exactly what will be copied, updated, or deleted
- **Parallel execution**: user-configurable thread count, multiple rsync processes per task
- **Network share auto-reconnect**: detect SMB disconnection, remount, resume transfer
- **Multiple simultaneous tasks**: run several sync operations at once with a global thread limit
- **Saved profiles**: persist sync configurations for re-use
- **Diagnostics**: speed, ETA, bottleneck indicator (disk vs network)
- **Per-task deletion policy**: macOS Trash, versioning folder, or permanent delete
- **Non-blocking UI**: all heavy work on background threads, zero spinning beach balls

### Non-Functional
- Full Disk Access (non-sandboxed)
- Bundled rsync 3.2.x (not the ancient macOS system rsync 2.6.9)
- Deploy to Gary's laptop via `scp` after each build

## Architecture

### Approach: rsync Process Manager

The app spawns rsync as child processes via Foundation `Process`. This leverages rsync's decades of edge-case handling for symlinks, permissions, extended attributes, resource forks, and delta-transfer. Parallelism is achieved by splitting the directory tree and running concurrent rsync instances.

### UI Layout (Three-Pane NavigationSplitView)

```
┌─────────────────────────────────────────────────────────────────────┐
│ TOOLBAR                                                             │
│ [+ New Task] [▶ Start] [⏸ Pause] [⏹ Stop]  |  Threads: [==4==]    │
│                                              |  [⚙ Settings]        │
└─────────────────────────────────────────────────────────────────────┘
┌──────────────┬──────────────────────────────────────┬───────────────┐
│  SIDEBAR     │  MAIN CONTENT AREA                   │  INSPECTOR    │
│              │                                      │  (toggle)     │
│ ─ Profiles ─ │  ┌─────────────────┬────────────────┐│               │
│  📁 Backup   │  │   SOURCE        │  DESTINATION   ││ Task Status   │
│  📁 Photos   │  │   /Volumes/HD1  │  //NAS/share   ││ ───────────── │
│  📁 Music    │  │                 │                ││ Mode: Mirror  │
│              │  │  file_a.txt  ►  │  file_a.txt    ││ Threads: 4    │
│ ─ Active ──  │  │  file_b.txt  ►  │  (new)         ││ Speed: 45MB/s │
│  🔄 Backup   │  │  file_c.txt  =  │  file_c.txt    ││ ETA: 12:34    │
│    45% ████░ │  │  (deleted)   ◄  │  file_d.txt    ││ Files: 234/1k │
│  🔄 Photos   │  │                 │                ││               │
│    12% █░░░░ │  └─────────────────┴────────────────┘│ Diagnostics   │
│              │                                      │ ───────────── │
│ ─ History ── │  PREVIEW BAR                         │ Bottleneck:   │
│  ✅ Music    │  [234 copy ► | 12 delete ✕ | 1.2GB] │   Network     │
│  ✅ Docs     │  [▶ Start Sync] [Cancel]             │ Disk Read:    │
│              │                                      │   120 MB/s    │
└──────────────┴──────────────────────────────────────┴───────────────┘
```

**Sidebar** — Collapsible sections (Profiles, Active Tasks with progress, History)
**Main Content** — Two-panel comparison (source left, destination right) with action icons
**Inspector** — Toggleable right panel with task config, live stats, diagnostics

### Data Model

```swift
// Persisted configuration
struct SyncProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var sourcePath: String
    var destinationPath: String
    var syncMode: SyncMode           // .synchronize, .mirror, .update
    var deletionPolicy: DeletionPolicy // .trash, .versioning(path), .permanent
    var threadCount: Int
    var filters: FilterConfig
    var rsyncExtraFlags: [String]
    var networkShareConfig: NetworkShareConfig?
}

enum SyncMode: String, Codable {
    case synchronize  // Bidirectional
    case mirror       // One-way with deletes
    case update       // One-way, no deletes
}

enum DeletionPolicy: Codable {
    case trash
    case versioning(path: String)
    case permanent
}

// Runtime state
class SyncTask: ObservableObject, Identifiable {
    let id: UUID
    let profile: SyncProfile
    @Published var phase: TaskPhase
    @Published var previewResults: [FileAction]
    @Published var progress: SyncProgress
    var rsyncProcesses: [Process]
    var networkMonitor: NetworkShareMonitor?
    var diagnostics: DiagnosticState
}

struct FileAction: Identifiable {
    let id: UUID
    let relativePath: String
    let action: ActionType    // .copyRight, .copyLeft, .equal, .deleteSource, .deleteDest
    let sourceSize: Int64?
    let destSize: Int64?
    let sourceModified: Date?
    let destModified: Date?
    var excluded: Bool        // User can exclude from sync
}
```

### Engine Components

#### 1. RsyncEngine
- Builds rsync commands from SyncProfile
- Preview: `rsync --dry-run --itemize-changes -avz --info=progress2`
- Execution: `rsync -avz --partial-dir=.macsync_partial --info=progress2`
- Mirror adds: `--delete --delete-during`
- Update adds: `--update` (skip newer files on dest)
- Synchronize: runs two passes (source→dest, then dest→source with conflict resolution)
- Parses stdout for progress and itemized file list
- Bundled binary at `MacSync.app/Contents/Resources/rsync`

#### 2. Parallel Execution
1. Walk source 1 level deep to get top-level entries
2. Distribute entries across N rsync processes (N = thread count)
3. Each process uses `--files-from` or `--include/--exclude` for its subtrees
4. Coordinator aggregates progress from all processes via AsyncStream
5. Small directories batched together to avoid underutilized processes

#### 3. NetworkShareMonitor
- Polls mount point with `stat()` every 5 seconds during active sync
- On disconnect: sends SIGSTOP to rsync processes
- Attempts `NetFSMountURLAsync` remount with Keychain-stored credentials
- On reconnect: sends SIGCONT, rsync resumes via `--partial-dir`
- Exponential backoff: 5s, 10s, 20s, 40s... max 2 minutes
- After 10 failures: mark task as failed, send macOS notification
- User can manually retry or cancel at any time

#### 4. TaskCoordinator
- Manages all active SyncTasks
- Enforces global thread limit across tasks
- Queue system: excess tasks wait until threads free up
- Each task isolated on its own DispatchQueue
- Aggregates diagnostics for the inspector

### Error Handling
- **rsync crash**: Detect via `Process.terminationHandler`, restart subtree with `--partial`
- **Permission denied**: Bubble to UI with file path, offer Skip or Retry
- **Disk full**: Detect from rsync exit code 11 / stderr, pause + notify
- **Network timeout**: Handled by NetworkShareMonitor reconnection flow

### Diagnostics
- **Bottleneck indicator**: Compare disk read vs network write speed
- **Transfer speed**: Aggregated MB/s from all rsync processes
- **ETA**: bytes_remaining / smoothed_speed
- **File counts**: completed / total files and bytes

### Data Persistence
- **Profiles**: JSON in `~/Library/Application Support/MacSync/Profiles/`
- **History**: SQLite via GRDB in `~/Library/Application Support/MacSync/history.db`
- **Settings**: UserDefaults (thread count, inspector visibility, window frame)
- **Credentials**: macOS Keychain via Security framework

### Technology Stack
- Swift 5.9+ / SwiftUI
- AppKit NSTableView (wrapped) for comparison table (100k+ row performance)
- Foundation Process for rsync
- Swift Concurrency (TaskGroup, AsyncStream)
- NetFS framework for SMB mounting
- Security framework for Keychain
- GRDB for SQLite history
- Non-sandboxed, Full Disk Access

### CI/CD
- Git repo synced to `gtbarnes/macsync` on GitHub
- On every build: `scp -r MacSync.app gary@Garys-Laptop.local:~/Applications/`
