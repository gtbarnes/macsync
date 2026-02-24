# MacSync Research Report
## Comprehensive Analysis for Building a macOS File Synchronization Application

*Compiled: 2026-02-24*

---

## Table of Contents

1. [FreeFileSync Features and UX Patterns](#1-freefilesync-features-and-ux-patterns)
2. [rsync on macOS](#2-rsync-on-macos)
3. [macOS Network Share Reconnection](#3-macos-network-share-reconnection)
4. [Multi-Threaded File Sync Approaches](#4-multi-threaded-file-sync-approaches)
5. [macOS-Specific Considerations](#5-macos-specific-considerations)

---

## 1. FreeFileSync Features and UX Patterns

### 1.1 Core Architecture

FreeFileSync (current version 14.8, released Feb 22, 2026) is a free, open-source file synchronization tool for Windows, macOS, and Linux. Its architecture separates the workflow into two distinct phases: **Compare** (detect differences) and **Synchronize** (apply changes). This two-phase approach is a key UX pattern that gives users confidence by letting them preview all changes before any files are modified.

### 1.2 Comparison Methods

FreeFileSync offers three comparison strategies:

| Method | How It Works | Speed | Use Case |
|--------|-------------|-------|----------|
| **File Time and Size** (default) | Files are identical when both modification time and file size match | Fast | Standard backup/sync scenarios |
| **File Content** | Bit-by-bit comparison of file data (no hashing -- full read comparison) | Slowest | Consistency verification, unreliable timestamps |
| **File Size Only** | Files are equal if they have the same size | Fastest | MTP devices, legacy FTP servers with unreliable timestamps |

After comparison, files are categorized into: left-only, right-only, left-newer, right-newer, equal, and conflict states.

**Symbolic link handling** offers two modes: "Follow" (treat as target) or "As link" (treat link object directly).

### 1.3 Sync Modes

**Two-Way Sync:**
- Changes flow in both directions (creates, updates, deletes)
- Creates database files (sync.ffs_db) after first sync to track previous state
- Subsequent syncs use the database to determine which side changed
- Detects moved files when file system supports file IDs (not FAT or SFTP)
- Handles conflicts when both sides change the same file

**Mirror Sync:**
- Left folder = source, right folder = target
- Creates and deletes files on the target until it is an exact copy of the source
- Most aggressive mode -- will delete files on the right that do not exist on the left

**Update Sync:**
- Only adds/updates files; never deletes
- Files deleted on source are NOT deleted on backup
- Files deleted on backup are NOT re-copied
- Ideal for camera backups or accumulative archives

**Custom Sync:**
- User defines actions per comparison category (left-only, right-only, left-newer, right-newer)
- Can optionally use database file to detect create/update/delete changes
- Maximum flexibility for special sync scenarios

### 1.4 UI Layout and UX Patterns

**Dual-Panel Comparison View:**
- Two folders displayed side-by-side (left panel, right panel)
- Files are matched and aligned between panels
- Visual indicators show the status of each file pair:
  - Present on one side only
  - Different (with newer/older indication)
  - Equal (matching)
  - Conflict (ambiguous state)

**Sync Direction Indicators:**
- A center column between the two panels shows proposed sync actions using directional arrows
- Users can hover over the lightning/arrow symbol and click to override the sync direction for individual files
- This per-file override capability is a critical UX feature for user confidence

**Primary Action Buttons:**
- Three main actions occupy prominent positions: Compare, Synchronize, Setup
- Touch targets are large (at least 24pt) following Fitts' Law principles
- Secondary controls (filters, versioning, scheduling) are grouped under collapsible panels

**Key UX Takeaways:**
1. Preview before action: always show what will happen before doing it
2. Per-item override: let users change the action for individual files
3. Clear visual language: use color-coding and icons for file states
4. Separation of concerns: compare first, then sync
5. Configuration persistence: save configurations as reusable .ffs_gui or .ffs_batch files

### 1.5 Filter System

**Include/Exclude Filters:**
- Files pass the filter only if they match at least one include entry AND no exclude entries
- Filters use relative paths from the selected folder pair
- Multiple items separated by `|` or newlines

**Wildcard Syntax:**
- `*` matches zero or more characters (including path separators!)
- `?` matches exactly one character
- Matching is case-insensitive
- Trailing `\` restricts matching to directories only

**Common Filter Patterns:**
- Single folder: `\SubFolder\`
- All files with a name: `*\thumbs.db`
- Files in specific folder only: `\SubFolder\*.tmp`
- All .DS_Store files: `*\.DS_Store`

**Important:** The `*` wildcard is eager across path separators, which can produce unexpected matches in nested directory structures.

**Limitation:** FreeFileSync does not appear to have built-in time-based or file-size-based filtering in its standard filter configuration dialog.

### 1.6 Batch Jobs

- Save any sync configuration as a `.ffs_batch` file via Menu > File > Save as Batch Job
- Batch files encode: source/destination paths, comparison method, sync method, filters
- Can define multiple left-right folder pairs in a single batch job with per-pair settings
- Batch jobs can be scheduled via OS task schedulers (cron, Windows Task Scheduler, launchd)
- Can specify error handling behavior (popup, log, abort)
- Email notifications available in batch mode

### 1.7 RealTimeSync

- Companion application that monitors directories for changes
- Receives change notifications directly from the OS (no polling)
- Waits for a configurable idle time after changes stop before triggering
- Typically configured to run a FreeFileSync batch job when changes are detected
- **Limitation:** RealTimeSync does not support filters -- any change in monitored directories triggers the batch job, even if those changes would be filtered out during sync

### 1.8 Deletion Handling / Versioning

Three options for how deleted/overwritten files are handled:

1. **Recycler**: Moves to system recycle bin
2. **Versioning**: Moves files to a versioning folder with naming options:
   - *Replace*: Overwrites previous versions
   - *Time-stamped*: Appends timestamp to filenames
   - Supports macros in versioning folder paths for granularity control
3. **Permanent**: Deletes files permanently

### 1.9 Database File (sync.ffs_db)

- Created by two-way sync variant to track the state of both sync sides
- Enables detection of: which side changed, file moves/renames, deletions
- Without the database, FreeFileSync cannot distinguish between "file created on left" vs "file deleted on right"
- Can be safely deleted; will be recreated on next sync (but first sync after deletion acts like initial sync)

---

## 2. rsync on macOS

### 2.1 The macOS rsync Situation (Critical Issue)

**Historical Problem:**
macOS shipped with rsync 2.6.9 (from 2006) for over a decade due to Apple's refusal to adopt GPLv3-licensed software. This version lacked many features from rsync 3.x.

**macOS Sequoia (15.x) Changes:**
Apple has now replaced rsync entirely with **openrsync**, an ISC-licensed reimplementation originally from the OpenBSD project:

- macOS 15.0-15.3: Shipped both rsync.samba and rsync.openrsync with a wrapper that dispatched to either
- macOS 15.4+: Removed rsync.samba entirely, making openrsync the sole default
- openrsync accepts only a **subset** of rsync's command-line arguments

**Known openrsync Limitations:**
- Missing `--log-file` parameter
- Missing or broken `--backup-dir` functionality
- Incompatible with `user@host::share` syntax (must use `rsync://user@host/share`)
- Script failures with "Assertion failed" and "Abort trap: 6" errors
- Protocol compatibility issues with rsync servers on other platforms (partially fixed in 15.6.1)
- Excessive CPU wake violations reported

**Recommendation for MacSync:**
Bundle rsync 3.x via Homebrew (`brew install rsync`, currently version 3.4.1) or ship a compiled binary of rsync 3.x alongside the application. The built-in macOS rsync/openrsync is NOT reliable enough for a production sync application. The Homebrew rsync installs to `/opt/homebrew/bin/rsync` (Apple Silicon) or `/usr/local/bin/rsync` (Intel). Note: Installing Homebrew's rsync breaks Apple's openrsync symlink.

**Alternative:** Ship a statically-compiled rsync binary within the app bundle to avoid dependency on Homebrew.

### 2.2 rsync Flags for Different Sync Modes

#### Mirror Mode (Source -> exact copy on Destination)
```bash
rsync -avz --delete /source/ /destination/
```
- `-a` (archive): Recursive, preserves permissions, ownership, timestamps, symlinks, devices, specials
- `-v` (verbose): Show files being transferred
- `-z` (compress): Compress during transfer (useful for network, skip for local)
- `--delete`: Remove files from destination that no longer exist in source

#### Update Mode (Only copy newer files)
```bash
rsync -avz --update /source/ /destination/
```
- `--update` (`-u`): Skip files that are newer on the destination

#### One-Way Sync (Additive, no deletions)
```bash
rsync -avz /source/ /destination/
```
- Standard archive mode without `--delete`

#### Common Additional Flags
```bash
# Preserve macOS-specific metadata
rsync -avzE --protect-args /source/ /destination/

# With partial transfer support
rsync -avz --partial --partial-dir=.rsync-partial /source/ /destination/

# Full feature set for macOS
rsync -avzHAX --delete --progress /source/ /destination/
```

**Critical flag explanations:**
- `-E` (Apple-specific): Preserve extended attributes using AppleDouble format (creates `._filename` files on non-HFS+/APFS destinations)
- `-H`: Preserve hard links
- `-A`: Preserve ACLs
- `-X`: Preserve extended attributes (standard, different from Apple's `-E`)
- `--protect-args`: Protect arguments with spaces

### 2.3 Preview / Dry-Run Functionality

```bash
rsync -avz --dry-run --delete /source/ /destination/
```

- `--dry-run` (`-n`): Simulates the transfer, reports what would happen
- Best combined with `-v` and/or `--itemize-changes` for detailed output
- Always use dry-run before `--delete` operations to prevent accidental data loss

#### Itemized Changes Output (Machine-Parseable)
```bash
rsync -avz --dry-run --itemize-changes /source/ /destination/
```

Output format: `YXcstpoguax filename`

| Position | Meaning |
|----------|---------|
| Y | Update type: `<` = sent, `>` = received, `c` = local change, `.` = not updated |
| X | File type: `f` = file, `d` = directory, `L` = symlink, `D` = device |
| c | Checksum differs |
| s | Size differs |
| t | Modification time differs |
| p | Permissions differ |
| o | Owner differs |
| g | Group differs |
| u | Reserved |
| a | ACL differs |
| x | Extended attributes differ |

A `.` in any position means that attribute is unchanged. This format is ideal for programmatic parsing to build a preview UI similar to FreeFileSync's comparison view.

### 2.4 Progress Reporting

**Per-File Progress:**
```bash
rsync -avz --progress /source/ /destination/
```

**Overall Transfer Progress:**
```bash
rsync -avz --info=progress2 /source/ /destination/
```
Output format: `bytes_transferred  percentage  speed  time_remaining`
Example: `458,588,160  6%  109.38MB/s  0:01:02`

**Programmatic Parsing Considerations:**
- rsync uses carriage returns (`\r`) to update progress in-place
- Must convert `\r` to `\n` for line-by-line parsing: `stdbuf -oL tr '\r' '\n'`
- Every stage of a pipe must use `stdbuf -oL` for line buffering
- Use `--no-inc-recursive` for accurate percentage (does full file scan upfront, but slower start)
- Combine `-P` (equals `--partial --progress`) for resumable transfers with progress

**For a GUI application, recommended approach:**
1. First pass: `rsync --dry-run --itemize-changes` to build the file list and estimate total work
2. Second pass: `rsync --info=progress2 --no-inc-recursive` for transfer with accurate progress
3. Parse progress output line by line from stdout, extracting percentage and speed

### 2.5 Bandwidth Limiting

```bash
rsync -avz --bwlimit=5000 /source/ /destination/
```

- `--bwlimit=RATE`: Limit transfer rate in KBytes/second
- Supports suffixes: `--bwlimit=1.5m` = 1.5 MB/s
- Without suffix, unit is 1024 bytes (KiB/s)
- Works by writing data in blocks, then sleeping to maintain average rate
- Results in some "burstiness" (writes a block, sleeps, writes another)
- **Alternative:** Use `ionice` for I/O priority scheduling or `trickle` for application-level throttling

### 2.6 Resuming Interrupted Transfers

```bash
# Keep partial files for resume capability
rsync -avz --partial /source/ /destination/

# Better: use a partial directory to avoid incomplete files in destination
rsync -avz --partial-dir=.rsync-partial /source/ /destination/

# Use --append to resume from where transfer stopped
rsync -avz --append /source/ /destination/

# Combined approach for maximum resilience
rsync -avz -P --partial-dir=.rsync-partial /source/ /destination/
```

- `--partial`: Keep partially transferred files (normally deleted on interruption)
- `--partial-dir=DIR`: Store partial files in a separate directory (cleaner)
- `--append`: Resume by appending to partially transferred files
- `-P`: Shorthand for `--partial --progress`
- On re-run, rsync checks partial files and only transfers missing parts

---

## 3. macOS Network Share Reconnection

### 3.1 Detecting Mount Disconnections

**Approach 1: DiskArbitration Framework (Recommended for Swift)**

The DiskArbitration framework provides system-level notifications for disk/volume events:

```swift
import DiskArbitration

// Create a session
let session = DASessionCreate(kCFAllocatorDefault)

// Register for disk disappeared events
DARegisterDiskDisappearedCallback(
    session,
    nil,  // match dictionary (nil = all disks)
    { disk, context in
        // Handle disconnection
        let diskDescription = DADiskCopyDescription(disk) as? [String: Any]
        // Check if this is our network share
    },
    nil  // context
)

// Schedule on run loop
DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
```

Key callbacks available:
- `DARegisterDiskDisappearedCallback`: Called when a volume is unmounted/ejected
- `DARegisterDiskAppearedCallback`: Called when a new volume appears
- `DARegisterDiskDescriptionChangedCallback`: Called when disk properties change

An open-source Swift wrapper (DiskMonitor on GitHub) provides a higher-level interface that posts notifications for add/eject/rename events.

**Approach 2: File-Based Liveness Check (Simple, Reliable)**

A practical, battle-tested approach involves checking for a sentinel file on the mounted share:

```bash
#!/usr/bin/env bash
set -euo pipefail
[ -f /Volumes/sharename/.liveness.txt ] || osascript -e 'mount volume "smb://user@server/share"'
```

This script:
1. Checks if a known file exists on the mount point
2. If absent (mount is dead), remounts using AppleScript/Finder

**Approach 3: Polling Mount Points**

```bash
# Check if a share is mounted
mount | grep "//server/share"
# or
df | grep "/Volumes/sharename"
# or
stat /Volumes/sharename 2>/dev/null
```

### 3.2 Reconnecting to Network Shares

**Method 1: NetFS Framework (Recommended for Swift apps)**

```swift
import NetFS

let serverURL = URL(string: "smb://server.local/sharename")! as CFURL
let mountPath: CFURL? = nil  // Let system choose mount point
let user = "username" as CFString
let password = "password" as CFString

// Synchronous (avoid on main thread)
var mountPoints: Unmanaged<CFArray>?
let result = NetFSMountURLSync(
    serverURL,
    mountPath,
    user,
    password,
    nil,  // open_options
    nil,  // mount_options
    &mountPoints
)

if result == 0 {
    // Success - mountPoints contains the mount path(s)
} else {
    // Error - check errno.h for error codes
}

// Asynchronous (preferred)
var requestID: AsyncRequestID?
NetFSMountURLAsync(
    serverURL,
    mountPath,
    user,
    password,
    nil,  // open_options
    nil,  // mount_options
    &requestID,
    DispatchQueue.main,
    { status, requestID, mountPoints in
        if status == 0 {
            // Mount succeeded
        }
    }
)
```

**Important Notes:**
- Always prefer `NetFSMountURLAsync` over the synchronous variant
- In sandboxed apps, passing `nil` for mountPath will fail -- specify a path
- If user/password are nil, macOS presents the standard authentication dialog
- The NetFS framework works from within the sandbox

**Method 2: mount_smbfs (Command Line)**

```bash
# Basic mount
mount_smbfs //username:password@server.name/share_name /mount_point/

# macOS 10.15+ allows mounting to user directory without root
mkdir -p ~/mnt/sharename
mount_smbfs //user@server/share ~/mnt/sharename
```

**Method 3: AppleScript via Finder**

```swift
let script = NSAppleScript(source: """
    tell application "Finder"
        mount volume "smb://user@server/share"
    end tell
""")
script?.executeAndReturnError(nil)
```

**Method 4: open Command**

```bash
open "smb://user@server/share"
```

### 3.3 Persistent Monitoring Architecture

The recommended architecture for continuous mount monitoring combines:

1. **launchd Agent**: Runs a check script every 60 seconds via `StartInterval`
2. **Sentinel File Check**: Tests for a known file on the share
3. **Remount Logic**: Uses NetFS or AppleScript to remount on failure
4. **Alerting**: Notify via Notification Center or external service when remount fails
5. **Retry Logic**: Implement exponential backoff for repeated failures

Example launchd plist key settings:
```xml
<key>StartInterval</key>
<integer>60</integer>
<key>RunAtLoad</key>
<true/>
```

**Alternative: autofs**
macOS includes the autofs subsystem for automatic mounting on access, but it is complex, requires root-level LaunchDaemon configuration, and is recommended only for advanced users.

### 3.4 Resuming File Transfers After Network Interruption

For a sync application, the recommended approach:

1. **Use rsync's built-in resume**: `--partial-dir=.rsync-partial` keeps incomplete files separate
2. **Monitor mount health**: Before each sync operation, verify mount is available
3. **Implement retry logic**: On failure, wait, verify/remount share, then restart rsync
4. **Track progress**: Keep a manifest of successfully synced files so restart only processes remaining files
5. **Idempotent operations**: Ensure sync operations are safe to retry from any point

---

## 4. Multi-Threaded File Sync Approaches

### 4.1 How rclone Handles Parallelism

rclone (written in Go, MIT license) provides a sophisticated parallelism model:

**Two-Level Parallelism:**

| Flag | Default | Purpose |
|------|---------|---------|
| `--transfers` | 4 | Number of files transferred simultaneously |
| `--checkers` | 8 | Number of files checked (hash/metadata compared) simultaneously |
| `--multi-thread-streams` | 4 | Number of streams per individual file transfer |

**Architecture Details:**
- Checkers and transfers run concurrently -- files can be checked while others transfer
- Multi-thread-streams splits large files (default >256MB) into chunks transferred in parallel
- Each thread writes directly into the correct file position (using fallocate for preallocation)
- rclone preallocates files to avoid fragmentation or sparse files
- Thread buffer size is configurable per-thread to optimize write patterns
- `--max-connections` should be set to at least `--transfers + --checkers + 1`

**Backend-Aware:**
- rclone adjusts behavior per storage backend (local, S3, SMB, etc.)
- SMB backend supports multi-threaded transfers
- Backend capabilities marked as MultithreadUpload determine whether multi-thread-streams apply

**Key Lesson for MacSync:** Separate file checking (comparison) from file transfer into independent parallel pipelines, as rclone does.

### 4.2 Strategies for Parallelizing rsync

Since rsync is single-threaded by design, parallelism must be achieved at a higher level:

#### Strategy 1: File List Splitting with GNU Parallel

```bash
# Generate file list, split it, run parallel rsync instances
find /source/ -type f > /tmp/filelist.txt
split -n l/4 /tmp/filelist.txt /tmp/chunk_
parallel -j4 rsync -avz --files-from={} /source/ /destination/ ::: /tmp/chunk_*
```

**Pros:** Even distribution, works with any rsync version
**Cons:** Overhead of file list generation, splitting complexity

#### Strategy 2: Directory-Level Parallelism with xargs

```bash
# Find top-level directories and sync each in parallel
find /source/ -mindepth 1 -maxdepth 1 -type d | \
    xargs -n1 -P4 -I{} rsync -avz --delete {} /destination/
```

**Pros:** Simple, natural partitioning by directory
**Cons:** Uneven work distribution if directory sizes vary greatly

#### Strategy 3: GNU Parallel with Direct File List

```bash
find /source/ -type f | parallel -j10 -X rsync -zR -Ha ./{} server:/dest/
```

**Pros:** Fine-grained control, adjustable parallelism (`-j` flag)
**Cons:** High process overhead, many rsync instances

#### Strategy 4: Parsyncfp (Dedicated Parallel rsync Wrapper)

- Perl-based wrapper that manages multiple rsync instances
- Built-in load balancing based on system load monitoring
- Throttles by suspending/continuing rsync processes as needed
- Monitors system load and adjusts parallelism dynamically

**Pros:** Sophisticated load management
**Cons:** Perl dependency, additional complexity

#### Recommended Strategy for MacSync:
Use **directory-level parallelism** (Strategy 2) combined with file-level splitting for large directories. Implement in Swift using TaskGroup for clean concurrency management. Monitor system load and reduce parallelism if I/O saturation is detected.

### 4.3 Swift Concurrency for Parallel Transfers

**TaskGroup (Recommended Approach):**

```swift
func syncFiles(files: [SyncItem], maxConcurrency: Int) async throws {
    try await withThrowingTaskGroup(of: SyncResult.self) { group in
        var activeCount = 0
        var iterator = files.makeIterator()

        // Seed initial batch
        for _ in 0..<maxConcurrency {
            guard let file = iterator.next() else { break }
            group.addTask { try await self.syncFile(file) }
            activeCount += 1
        }

        // Process results and add new tasks
        for try await result in group {
            handleResult(result)
            if let nextFile = iterator.next() {
                group.addTask { try await self.syncFile(nextFile) }
            }
        }
    }
}
```

**Key Swift Concurrency Advantages:**
- **No thread explosion**: The Swift runtime limits the number of concurrent threads to the number of CPU cores (by default), preventing over-subscription
- **Structured concurrency**: Child tasks cannot outlive their parent TaskGroup scope, ensuring clean cleanup
- **AsyncSequence integration**: TaskGroup conforms to AsyncSequence, enabling streaming results
- **Cancellation propagation**: Cancelling the parent automatically cancels all children

**Design Pattern for File Sync:**
1. Use a TaskGroup with a sliding window of concurrent operations
2. Separate I/O-bound tasks (file reading/writing) from CPU-bound tasks (checksum computation)
3. Use `Task.yield()` in long-running operations to avoid thread starvation
4. Implement progress reporting via AsyncStream or Combine publishers

### 4.4 Avoiding Disk I/O Contention

**Research Findings on Optimal Thread Counts:**

| Scenario | Optimal Threads | Notes |
|----------|----------------|-------|
| SSD random I/O | 32-64+ | Up to 40x improvement vs single-threaded |
| SSD sequential I/O | 4-8 | Diminishes quickly after 8 threads |
| HDD random I/O | 16-32 | OS can reorder requests to minimize seeking |
| HDD sequential I/O | 1-2 | Multiple threads DEGRADE performance (2-10x slower) |
| NVMe (large I/O, >1MB) | 1-2 | Bandwidth saturated quickly |
| NVMe (small I/O, 4-64KB) | 16-64 | Benefit from internal parallelism |
| Network (SMB/NFS) | 4-8 | Limited by network bandwidth, not disk |

**Guidelines for MacSync:**

1. **Detect storage type**: Query IOKit to determine if target is SSD, HDD, or network volume
2. **Adaptive concurrency**: Start with fewer threads and increase while monitoring throughput
3. **Separate read/write pools**: Avoid reading and writing to the same disk simultaneously with too many threads
4. **Avoid cross-thread coordination**: Minimize shared state, locks, and synchronization points between transfer threads
5. **Buffer appropriately**: Larger buffers reduce syscall overhead but increase memory usage
6. **Batch small files**: Group many small file operations into fewer threads to reduce overhead
7. **Sequential for large files**: Use single-threaded transfer for very large files on HDD

**Practical default recommendations:**
- Local SSD-to-SSD: 8-16 concurrent file operations
- Local SSD-to-HDD: 2-4 concurrent file operations
- Network sync: 4-8 concurrent file operations (limited by bandwidth)
- Mixed (many small files): Higher concurrency (16-32) since per-file overhead dominates

---

## 5. macOS-Specific Considerations

### 5.1 Extended Attributes, Resource Forks, and ACLs

**Extended Attributes (xattr):**
- macOS files can carry arbitrary metadata via extended attributes
- Common xattrs: `com.apple.FinderInfo`, `com.apple.ResourceFork`, `com.apple.quarantine`
- rsync `-X` flag preserves standard extended attributes
- Apple's `-E` flag on rsync uses AppleDouble format (creates `._filename` companion files) for destinations that do not natively support xattr

**Resource Forks:**
- Legacy metadata format from Classic Mac OS, stored as extended attribute `com.apple.ResourceFork`
- Still used by some applications for icons, custom metadata
- When syncing to HFS+/APFS destinations, rsync copies resource forks natively
- When syncing to non-Apple filesystems, resource forks are stored in `._filename` AppleDouble files

**ACLs (Access Control Lists):**
- rsync `-A` flag preserves ACLs (implies `--perms`)
- macOS ACLs are richer than POSIX ACLs -- support allow/deny rules for specific users and groups
- When syncing to non-macOS destinations, ACLs may not be preserved

**Recommended rsync flags for full macOS metadata preservation:**
```bash
rsync -avzHAXE --delete /source/ /destination/
```

**For a Swift application, using FileManager:**
```swift
// copyItem preserves most metadata by default
try FileManager.default.copyItem(at: source, to: destination)

// For explicit control, use copyfile() system call
copyfile(sourcePath, destPath, nil, COPYFILE_ALL)
// COPYFILE_ALL = COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_DATA
```

### 5.2 APFS Cloning / Copy-on-Write Optimizations

**How APFS Cloning Works:**
- APFS supports copy-on-write at the file system level
- A "cloned" file shares disk blocks with the original -- no data is duplicated
- Only modified blocks diverge on disk when either copy is changed
- Clone operations are practically instantaneous (just metadata writes)
- Clones use negligible additional space until modifications occur

**API Options:**

| Function/Flag | Behavior |
|---------------|----------|
| `clonefile()` | Clone-only; fails if cloning not possible |
| `copyfile()` with `COPYFILE_CLONE` | Attempts clone, falls back to regular copy |
| `copyfile()` with `COPYFILE_CLONE_FORCE` | Clone-only; fails with error if not possible |
| `copyfile()` with `COPYFILE_DATA` | Always does full data copy, never clones |
| `cp -c` | Command-line clone |
| Finder duplicate | Uses COPYFILE_CLONE behavior (auto-fallback) |

**Performance:**
- `clonefile()` on a folder: ~10x faster than `FileManager.copyItem()`
- For 250 files: ~251 syscalls (copyItem) vs 1 syscall (clonefile)
- Zero additional disk I/O for the data

**Limitations:**
- Cloning only works within the **same APFS volume**
- Not available on HFS+, FAT, exFAT, or network filesystems
- Cannot clone across different APFS volumes (even on the same physical disk)

**Relevance to MacSync:**
- For local sync operations on the same volume, use `COPYFILE_CLONE` for massive performance gains
- For cross-volume or network sync, cloning is not applicable -- fall back to standard copy
- Detect APFS availability: check if source and destination are on the same APFS volume before attempting clone

```swift
// Check if two paths are on the same volume
func areOnSameVolume(_ path1: URL, _ path2: URL) -> Bool {
    let values1 = try? path1.resourceValues(forKeys: [.volumeIdentifierKey])
    let values2 = try? path2.resourceValues(forKeys: [.volumeIdentifierKey])
    guard let id1 = values1?.volumeIdentifier as? NSObject,
          let id2 = values2?.volumeIdentifier as? NSObject else { return false }
    return id1.isEqual(id2)
}
```

### 5.3 Spotlight Metadata Handling

**Files to Exclude from Sync:**
- `.DS_Store`: Finder view settings (present in every folder Finder has opened)
- `.Spotlight-V100/`: Spotlight index database directory
- `.fseventsd/`: File System Events daemon data
- `.Trashes/`: Trash directory on external volumes
- `._*`: AppleDouble resource fork files (created by rsync -E on non-Apple FS)

**rsync Exclusions for macOS:**
```bash
rsync -avz \
    --exclude '.DS_Store' \
    --exclude '.Spotlight-V100' \
    --exclude '.fseventsd' \
    --exclude '.Trashes' \
    --exclude '._*' \
    --exclude '.TemporaryItems' \
    /source/ /destination/
```

**CRITICAL:** Without `--exclude '.DS_Store'`, rsync can create hundreds of thousands of files named `..DS_Store.000000` due to metadata conflicts.

**Preventing Spotlight Indexing on Sync Destinations:**
- Append `.noindex` to the folder name (e.g., `Backup.noindex/`) -- still works in recent macOS
- The historical `.metadata_never_index` sentinel file no longer works in recent macOS versions
- Can exclude paths via System Settings > Siri & Spotlight > Privacy

**For MacSync:**
- Maintain a default exclusion list of macOS system files
- Allow users to customize exclusions
- Consider whether to sync or skip `.DS_Store` files (most sync tools skip them)

### 5.4 Sandboxing Considerations

**If Distributing via Mac App Store (Sandboxed):**

The App Sandbox restricts file system access to:
- The app's own container (`~/Library/Containers/com.example.app/`)
- User-selected files/folders (via Open/Save dialogs)
- Temporary directories

**Security-Scoped Bookmarks:**
- The primary mechanism for persistent file access in sandboxed apps
- Created when user selects files/folders via NSOpenPanel
- Stored as `Data` objects that can be persisted (e.g., in UserDefaults)
- Must call `startAccessingSecurityScopedResource()` before use
- Must call `stopAccessingSecurityScopedResource()` when done

```swift
// Create a bookmark when user selects a folder
let bookmark = try url.bookmarkData(
    options: .withSecurityScope,
    includingResourceValuesForKeys: nil,
    relativeTo: nil
)

// Later: resolve and access
var isStale = false
let resolvedURL = try URL(
    resolvingBookmarkData: bookmark,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)
_ = resolvedURL.startAccessingSecurityScopedResource()
defer { resolvedURL.stopAccessingSecurityScopedResource() }
// Now you can access files at resolvedURL
```

**Required Entitlements:**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

**If Distributing Outside App Store (Unsandboxed or Hardened Runtime):**
- Full Disk Access can be requested via System Settings > Privacy & Security
- User must manually add the app to the Full Disk Access list
- No programmatic way to request Full Disk Access -- must guide user through System Settings
- Hardened Runtime with the `com.apple.security.files.all` entitlement is another option

**NetFS from Sandbox:**
- `NetFSMountURLAsync` works from within the sandbox
- However, you MUST specify a mount path (cannot pass nil)
- The mount path must be within your accessible scope

**Recommendations for MacSync:**
- For maximum file access, distribute outside the Mac App Store with Hardened Runtime
- Request Full Disk Access entitlement for unrestricted file operations
- If App Store distribution is required, use security-scoped bookmarks for all sync folder pairs
- Cache bookmarks persistently so users do not need to re-select folders on each launch
- Handle bookmark staleness (files moved, volumes renamed) gracefully

---

## Summary of Key Architectural Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| rsync version | Bundle rsync 3.4.x | macOS built-in openrsync is unreliable |
| Preview/comparison | rsync --dry-run --itemize-changes | Machine-parseable, comprehensive |
| Progress reporting | rsync --info=progress2 --no-inc-recursive | Accurate overall percentage |
| Parallelism model | Swift TaskGroup + directory-level rsync parallelism | Clean concurrency, no thread explosion |
| Concurrency defaults | 4-8 for network, 8-16 for local SSD | Adaptive based on storage type |
| Network share monitoring | DiskArbitration + sentinel file check | Dual approach for reliability |
| Network share reconnection | NetFSMountURLAsync | Native API, works in sandbox |
| Local same-volume copy | COPYFILE_CLONE | Near-instant, zero I/O |
| Metadata preservation | rsync -HAXE flags | Full macOS metadata support |
| macOS system files | Default exclusion list | .DS_Store, .Spotlight-V100, etc. |
| Distribution model | Outside App Store + Full Disk Access | Maximum file access capability |
| Deletion safety | Versioning folder or recycler | Never permanently delete without user consent |
| Configuration persistence | .ffs_batch-style config files | Reusable, schedulable sync jobs |

---

## Sources

### FreeFileSync
- [FreeFileSync Official Site](https://freefilesync.org/)
- [FreeFileSync Comparison Settings](https://freefilesync.org/manual.php?topic=comparison-settings)
- [FreeFileSync Synchronization Settings](https://freefilesync.org/manual.php?topic=synchronization-settings)
- [FreeFileSync Exclude Files](https://freefilesync.org/manual.php?topic=exclude-files)
- [FreeFileSync Batch Jobs](https://freefilesync.org/manual.php?topic=schedule-batch-jobs)
- [FreeFileSync Versioning](https://freefilesync.org/manual.php?topic=versioning)
- [FreeFileSync RealTimeSync Documentation](https://documentation.help/FreeFileSync/RealtimeSync.html)

### rsync on macOS
- [rsync Replaced with openrsync on macOS Sequoia](https://derflounder.wordpress.com/2025/04/06/rsync-replaced-with-openrsync-on-macos-sequoia/)
- [Apple's Switch from rsync to openrsync](https://appleinsider.com/inside/macos-sequoia/tips/what-you-should-know-about-apples-switch-from-rsync-to-openrsync)
- [Updating rsync on macOS](https://dev.to/al5ina5/updating-rsync-on-macos-so-you-re-not-stuck-with-14-year-old-software-1b5i)
- [rsync Homebrew Formula](https://formulae.brew.sh/formula/rsync)
- [rsync Man Page](https://linux.die.net/man/1/rsync)
- [How to Use Rsync - DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-use-rsync-to-sync-local-and-remote-directories)
- [rsync Cheat Sheet](https://www.ditig.com/rsync-cheat-sheet)
- [rsync Progress Reporting](https://www.cyberciti.biz/faq/show-progress-during-file-transfer/)
- [Overall rsync Progress](https://www.dribin.org/dave/blog/archives/2024/01/21/rsync-overall-progress/)
- [rsync Bandwidth Limiting](https://www.cyberciti.biz/faq/how-to-set-keep-rsync-from-using-all-your-bandwidth-on-linux-unix/)
- [rsync --itemize-changes Output](https://gist.github.com/sblask/c551442f28d8f700579832ce5a80eca9)
- [rsync Resume Transfers](https://www.cyberciti.biz/faq/rsync-resume-partially-transferred-downloaded-files-option/)
- [Rsync Tips Collection](https://gist.github.com/ChristopherA/c07a1dfc9213cb3ab279b8e5e4298a92)

### Parallel rsync
- [How to Parallelize rsync - Baeldung](https://www.baeldung.com/linux/rsync-parallelize)
- [Parallel rsync with GNU Parallel](https://github.com/nathanhaigh/parallel-rsync)
- [parsyncfp - Parallel rsync Wrapper](http://moo.nac.uci.edu/~hjm/parsync/)
- [4x Faster Sync with rclone vs rsync](https://www.jeffgeerling.com/blog/2025/4x-faster-network-file-sync-rclone-vs-rsync/)

### rclone Architecture
- [rclone Documentation](https://rclone.org/docs/)
- [rclone vs rsync - Pure Storage](https://blog.purestorage.com/purely-technical/rclone-vs-rsync/)
- [rclone Multi-thread Streams Discussion](https://forum.rclone.org/t/using-multi-thread-streams-and-transfers/45949)

### macOS Network Shares
- [Mounting Network Share in Swift - Apple Forums](https://developer.apple.com/forums/thread/94733)
- [Keeping SMB Share Mounted on macOS](https://www.dzombak.com/blog/2024/03/keeping-a-smb-share-mounted-on-macos-and-alerting-when-it-does-down/)
- [Auto-mounting Network Shares on macOS](https://www.ctrl.blog/entry/automount-netshare-macos.html)
- [mount_smbfs Usage](https://gist.github.com/natritmeyer/6621231)
- [Swift NetFS Wrapper](https://gist.github.com/mosen/2ddf85824fbb5564aef527b60beb4669)
- [AMSMB2 - Swift SMB Framework](https://github.com/amosavian/AMSMB2)

### macOS Disk/Volume Monitoring
- [DiskArbitration Framework](https://developer.apple.com/documentation/diskarbitration)
- [DiskMonitor Swift Wrapper](https://github.com/stoqn4opm/DiskMonitor)
- [DADiskAppearedCallback](https://developer.apple.com/documentation/diskarbitration/dadiskappearedcallback)

### Disk I/O Performance
- [Performance Impact of Parallel Disk Access](https://pkolaczk.github.io/disk-parallelism/)

### APFS and File System
- [Copy-on-Write on APFS](https://wadetregaskis.com/copy-on-write-on-apfs/)
- [APFS Clones and Space Efficiency](http://dtrace.org/blogs/ahl/2016/06/19/apfs-part3/)
- [Copy, Move, and Clone Files in APFS](https://eclecticlight.co/2020/04/14/copy-move-and-clone-files-in-apfs-a-primer/)
- [SwiftCopyfile Library](https://github.com/osy/SwiftCopyfile)

### Swift Concurrency
- [TaskGroup in Swift - SwiftLee](https://www.avanderlee.com/concurrency/task-groups-in-swift/)
- [Running Multiple Tasks in Parallel - Swift by Sundell](https://www.swiftbysundell.com/articles/swift-concurrency-multiple-tasks-in-parallel/)
- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

### macOS Sandboxing
- [Accessing Files from App Sandbox - Apple](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Security-Scoped Bookmarks - Apple](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [Understanding File Access in Sandboxed Apps](https://codebit-inc.com/blog/mastering-file-access-macos-sandboxed-apps/)

### Spotlight and Metadata
- [How to Sync with rsync but Ignore .DS_Store](https://dimasmaulana.dev/posts/development/how-to-sync-with-rsync-but-ignore-dsstore-files/)
- [Excluding from Spotlight Indexing](https://macmegasite.com/2024/07/09/excluding-folders-and-files-from-time-machine-spotlight-and-icloud-drive/)
