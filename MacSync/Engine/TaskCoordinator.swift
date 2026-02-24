import Foundation

@MainActor
final class TaskCoordinator {
    private weak var appState: AppState?
    private let engine = RsyncEngine()

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Compare (Preview)

    /// Creates a SyncTask, runs rsync dry-run preview, and updates previewResults on completion.
    func compareTask(for profile: SyncProfile) {
        guard let appState else { return }

        // Check if there's already an active task for this profile
        if appState.activeTasks.contains(where: { $0.profile.id == profile.id && $0.phase.isActive }) {
            return // Already running
        }

        let task = SyncTask(profile: profile)
        task.phase = .comparing
        task.comparisonStartTime = Date()
        appState.activeTasks.append(task)
        appState.sidebarSelection = .activeTask(task.id)

        Task {
            // Check path permissions off the main thread
            let permService = PermissionService.shared
            let sourceError = await Task.detached {
                permService.checkPathAccess(profile.sourcePath, role: .source)
            }.value
            if let sourceError {
                task.phase = .failed
                task.errorMessage = sourceError
                appState.pathAccessAlertMessage = sourceError
                appState.showPathAccessAlert = true
                return
            }
            let destError = await Task.detached {
                permService.checkPathAccess(profile.destinationPath, role: .destination)
            }.value
            if let destError {
                task.phase = .failed
                task.errorMessage = destError
                appState.pathAccessAlertMessage = destError
                appState.showPathAccessAlert = true
                return
            }

            do {
                // Log the rsync command to the console
                let builder = RsyncCommandBuilder(profile: profile)
                let cmd = builder.buildPreviewCommand()
                task.appendConsoleOutput("$ \(cmd.executablePath) \(cmd.allArguments.joined(separator: " "))\n\n")

                let stream = await engine.preview(profile: profile) { [weak task] rawChunk in
                    Task { @MainActor in
                        task?.appendConsoleOutput(rawChunk)
                    }
                }
                for try await actions in stream {
                    guard !task.isCancelled else { break }
                    // Append only the delta to avoid O(n²) re-renders
                    let previousCount = task.previewResults.count
                    let newItems = actions.dropFirst(previousCount)
                    if !newItems.isEmpty {
                        task.previewResults.append(contentsOf: newItems)
                        task.lastScannedPath = newItems.last?.relativePath
                    }
                }
                if !task.isCancelled {
                    task.phase = .previewing
                }
            } catch {
                task.phase = .failed
                task.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Execute Sync

    /// Runs the actual rsync sync for a task that already has preview results.
    func executeSyncTask(_ task: SyncTask) {
        guard let appState else { return }

        task.phase = .syncing
        task.progress = SyncProgress()
        task.progress.startTime = Date()

        // Calculate totals from preview
        task.progress.totalFiles = task.previewResults.filter {
            $0.action == .copyRight || $0.action == .copyLeft
        }.count
        task.progress.totalBytes = task.previewResults.compactMap {
            $0.sourceSize ?? $0.destSize
        }.reduce(0, +)

        // Log the sync command to the console
        let builder = RsyncCommandBuilder(profile: task.profile)
        let cmd = builder.buildSyncCommand()
        task.appendConsoleOutput("\n--- Sync Started ---\n")
        task.appendConsoleOutput("$ \(cmd.executablePath) \(cmd.allArguments.joined(separator: " "))\n\n")

        Task {
            do {
                let processes = try await engine.sync(
                    profile: task.profile,
                    onProgress: { [weak task] progress in
                        Task { @MainActor in
                            guard let task else { return }
                            task.progress.transferredBytes = progress.transferredBytes
                            task.progress.currentSpeed = progress.currentSpeed
                            task.progress.smoothedSpeed = progress.smoothedSpeed
                        }
                    },
                    onRawOutput: { [weak task] rawChunk in
                        Task { @MainActor in
                            task?.appendConsoleOutput(rawChunk)
                        }
                    }
                )
                task.rsyncProcesses = processes
                task.phase = .completed
                recordHistory(task: task, success: true)

                // Update profile's last synced date
                if var profile = appState.profiles.first(where: { $0.id == task.profile.id }) {
                    profile.lastSyncedAt = Date()
                    appState.saveProfile(profile)
                }
            } catch is CancellationError {
                task.phase = .failed
                task.errorMessage = "Cancelled by user"
            } catch {
                task.phase = .failed
                task.errorMessage = error.localizedDescription
                recordHistory(task: task, success: false)
            }
        }
    }

    // MARK: - Pause

    /// Suspends all running rsync processes (SIGSTOP).
    func pauseTask(id: UUID) {
        guard let appState else { return }
        guard let task = appState.activeTasks.first(where: { $0.id == id }) else { return }

        for process in task.rsyncProcesses where process.isRunning {
            process.suspend()
        }
        task.phase = .paused
    }

    // MARK: - Resume

    /// Resumes all suspended rsync processes (SIGCONT).
    func resumeTask(id: UUID) {
        guard let appState else { return }
        guard let task = appState.activeTasks.first(where: { $0.id == id }) else { return }

        for process in task.rsyncProcesses where process.isRunning {
            process.resume()
        }
        task.phase = .syncing
    }

    // MARK: - Stop

    /// Terminates all running rsync processes (SIGTERM).
    func stopTask(id: UUID) {
        guard let appState else { return }
        guard let task = appState.activeTasks.first(where: { $0.id == id }) else { return }

        task.isCancelled = true
        for process in task.rsyncProcesses where process.isRunning {
            process.terminate()
        }
        task.phase = .failed
        task.errorMessage = "Cancelled by user"
    }

    // MARK: - History

    /// Records a completed or failed task in the history.
    private func recordHistory(task: SyncTask, success: Bool) {
        guard let appState else { return }

        let entry = CompletedTask(
            id: UUID(),
            profileName: task.profile.name,
            syncMode: task.profile.syncMode,
            startTime: task.progress.startTime ?? Date(),
            endTime: Date(),
            filesTransferred: task.progress.completedFiles,
            bytesTransferred: task.progress.transferredBytes,
            errors: success ? 0 : 1,
            success: success
        )
        appState.taskHistory.insert(entry, at: 0)
        appState.historyStore.save(entry)
    }
}
