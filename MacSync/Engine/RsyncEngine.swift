import Foundation

enum RsyncError: LocalizedError {
    case processError(String)
    case networkDisconnected
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processError(let message): return "rsync error: \(message)"
        case .networkDisconnected: return "Network connection lost"
        case .cancelled: return "Cancelled by user"
        }
    }
}

actor RsyncEngine {

    // MARK: - Preview (Dry Run)

    /// Runs rsync in dry-run mode and streams parsed FileAction results as they arrive.
    ///
    /// Uses a blocking read loop on a background thread instead of readabilityHandler
    /// to avoid a race condition where terminationHandler can fire before
    /// readabilityHandler processes pipe data, causing 0 results.
    func preview(profile: SyncProfile) -> AsyncThrowingStream<[FileAction], Error> {
        AsyncThrowingStream { continuation in
            let builder = RsyncCommandBuilder(profile: profile)
            let command = builder.buildPreviewCommand()

            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executablePath)
            process.arguments = command.allArguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: RsyncError.processError(error.localizedDescription))
                return
            }

            // Read stdout on a background thread. availableData blocks until
            // data arrives or the pipe closes (EOF). This single-threaded approach
            // guarantees all pipe data is consumed before we check the exit status.
            DispatchQueue.global(qos: .userInitiated).async {
                var accumulatedActions: [FileAction] = []
                var lineBuffer = ""
                let fileHandle = stdoutPipe.fileHandleForReading

                // Read until EOF (pipe closed when process exits)
                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty { break } // EOF — process closed stdout
                    guard let chunk = String(data: data, encoding: .utf8) else { continue }

                    lineBuffer += chunk
                    let lines = lineBuffer.components(separatedBy: "\n")
                    lineBuffer = lines.last ?? ""

                    let completeLines = lines.dropLast()
                    for line in completeLines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        let parsed = RsyncOutputParser.parseItemizedChanges(trimmed, syncMode: profile.syncMode)
                        if !parsed.isEmpty {
                            accumulatedActions.append(contentsOf: parsed)
                            continuation.yield(accumulatedActions)
                        }
                    }
                }

                // Process any remaining partial line in the buffer
                let remaining = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !remaining.isEmpty {
                    let parsed = RsyncOutputParser.parseItemizedChanges(remaining, syncMode: profile.syncMode)
                    if !parsed.isEmpty {
                        accumulatedActions.append(contentsOf: parsed)
                        continuation.yield(accumulatedActions)
                    }
                }

                // All pipe data is consumed. Wait for process to fully exit.
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

                    if errorMessage.contains("connection") || errorMessage.contains("network") {
                        continuation.finish(throwing: RsyncError.networkDisconnected)
                    } else {
                        continuation.finish(throwing: RsyncError.processError(errorMessage))
                    }
                }
            }
        }
    }

    // MARK: - Sync (Actual Transfer)

    /// Runs rsync to perform the actual sync. Returns the list of Process objects
    /// for external control (pause/resume/stop).
    ///
    /// - Parameters:
    ///   - profile: The sync profile to execute
    ///   - onProgress: Callback with updated SyncProgress, called on an arbitrary thread
    /// - Returns: Array of Process objects used for the sync
    func sync(
        profile: SyncProfile,
        onProgress: @escaping @Sendable (SyncProgress) -> Void
    ) async throws -> [Process] {
        if profile.threadCount <= 1 {
            return try await runSingleSync(profile: profile, onProgress: onProgress)
        } else {
            return try await runParallelSync(profile: profile, onProgress: onProgress)
        }
    }

    // MARK: - Single Process Sync

    private func runSingleSync(
        profile: SyncProfile,
        onProgress: @escaping @Sendable (SyncProgress) -> Void
    ) async throws -> [Process] {
        let builder = RsyncCommandBuilder(profile: profile)
        let command = builder.buildSyncCommand()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.allArguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var progress = SyncProgress()
        progress.startTime = Date()

        try process.run()

        // Read stdout on a background thread using a blocking loop.
        // Same pattern as preview() — avoids readabilityHandler/terminationHandler race.
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileHandle = stdoutPipe.fileHandleForReading

                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty { break }
                    guard let line = String(data: data, encoding: .utf8) else { continue }

                    if let parsed = RsyncOutputParser.parseProgress(line) {
                        progress.transferredBytes = parsed.bytesTransferred
                        progress.currentSpeed = parsed.speed
                        progress.smoothedSpeed = 0.8 * progress.smoothedSpeed + 0.2 * parsed.speed
                        onProgress(progress)
                    }
                }

                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: [process])
                } else if process.terminationStatus == 20 {
                    continuation.resume(throwing: RsyncError.cancelled)
                } else {
                    let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: RsyncError.processError(errorMessage))
                }
            }
        }
    }

    // MARK: - Parallel Sync

    private func runParallelSync(
        profile: SyncProfile,
        onProgress: @escaping @Sendable (SyncProgress) -> Void
    ) async throws -> [Process] {
        let entries = topLevelEntries(at: profile.sourcePath)
        guard !entries.isEmpty else {
            return try await runSingleSync(profile: profile, onProgress: onProgress)
        }

        let chunks = distributeEntries(entries, across: profile.threadCount)
        let progressLock = NSLock()
        var aggregatedProgress = SyncProgress()
        aggregatedProgress.startTime = Date()

        // Use a lock-protected array to collect processes from all tasks
        let processesLock = NSLock()
        var allProcesses: [Process] = []

        try await withThrowingTaskGroup(of: [Process].self) { group in
            for chunk in chunks where !chunk.isEmpty {
                group.addTask {
                    let tempPath = try self.writeFilesFromList(chunk)
                    let builder = RsyncCommandBuilder(profile: profile)
                    let command = builder.buildSyncCommand(filesFrom: tempPath)

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: command.executablePath)
                    process.arguments = command.allArguments

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    // Track this process
                    processesLock.lock()
                    allProcesses.append(process)
                    processesLock.unlock()

                    try process.run()

                    // Blocking read loop — same pattern as preview() and runSingleSync().
                    return try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .userInitiated).async {
                            let fileHandle = stdoutPipe.fileHandleForReading

                            while true {
                                let data = fileHandle.availableData
                                if data.isEmpty { break }
                                guard let line = String(data: data, encoding: .utf8) else { continue }

                                if let parsed = RsyncOutputParser.parseProgress(line) {
                                    progressLock.lock()
                                    aggregatedProgress.transferredBytes += parsed.bytesTransferred
                                    aggregatedProgress.currentSpeed = parsed.speed
                                    aggregatedProgress.smoothedSpeed =
                                        0.8 * aggregatedProgress.smoothedSpeed + 0.2 * parsed.speed
                                    let snapshot = aggregatedProgress
                                    progressLock.unlock()
                                    onProgress(snapshot)
                                }
                            }

                            process.waitUntilExit()

                            // Clean up temp file
                            try? FileManager.default.removeItem(atPath: tempPath)

                            if process.terminationStatus == 0 {
                                continuation.resume(returning: [process])
                            } else if process.terminationStatus == 20 {
                                continuation.resume(throwing: RsyncError.cancelled)
                            } else {
                                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                                continuation.resume(throwing: RsyncError.processError(errorMessage))
                            }
                        }
                    }
                }
            }

            // Collect results
            for try await _ in group { }
        }

        processesLock.lock()
        let result = allProcesses
        processesLock.unlock()
        return result
    }

    // MARK: - Helper: List Top-Level Entries

    /// Lists top-level entries in the source directory (excluding hidden files).
    nonisolated func topLevelEntries(at path: String) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return entries.filter { !$0.hasPrefix(".") }
    }

    // MARK: - Helper: Distribute Entries

    /// Round-robin distributes entries across N chunks.
    nonisolated func distributeEntries(_ entries: [String], across count: Int) -> [[String]] {
        var chunks = Array(repeating: [String](), count: count)
        for (index, entry) in entries.enumerated() {
            chunks[index % count].append(entry)
        }
        return chunks
    }

    // MARK: - Helper: Write Files-From List

    /// Writes entries to a temporary file for rsync's `--files-from` argument.
    nonisolated func writeFilesFromList(_ entries: [String]) throws -> String {
        let tempDir = NSTemporaryDirectory()
        let tempFile = tempDir + "macsync_fileslist_\(UUID().uuidString).txt"
        let content = entries.joined(separator: "\n") + "\n"
        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)
        return tempFile
    }
}
