import Foundation
import Combine

/// Thread-safe buffer for accumulating raw rsync output on background threads.
/// Drained periodically by the main actor to batch UI updates.
final class ConsoleBuffer: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    func append(_ text: String) {
        lock.lock()
        buffer += text
        lock.unlock()
    }

    func drain() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let result = buffer
        buffer = ""
        return result
    }
}

@MainActor
class SyncTask: ObservableObject, Identifiable {
    let id: UUID
    let profile: SyncProfile
    @Published var phase: TaskPhase = .idle
    @Published var previewResults: [FileAction] = []
    @Published var progress: SyncProgress = SyncProgress()
    @Published var errorMessage: String?
    @Published var diagnostics: DiagnosticState = DiagnosticState()
    @Published var lastScannedPath: String?
    @Published var consoleOutput: String = ""
    let consoleBuffer = ConsoleBuffer()
    var comparisonStartTime: Date?
    var rsyncProcesses: [Process] = []
    var isCancelled: Bool = false

    private var consoleFlushTask: Task<Void, Never>?

    init(profile: SyncProfile) {
        self.id = UUID()
        self.profile = profile
    }

    // MARK: - Console Buffering

    /// Starts a background loop that drains the console buffer every 300ms.
    /// This batches rapid rsync output into ~3 UI updates/second instead of
    /// thousands, preventing runaway memory from queued MainActor tasks.
    func startConsoleFlush() {
        guard consoleFlushTask == nil else { return }
        consoleFlushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { break }
                self?.flushConsoleBuffer()
            }
        }
    }

    /// Stops the flush loop and performs a final drain.
    func stopConsoleFlush() {
        consoleFlushTask?.cancel()
        consoleFlushTask = nil
        flushConsoleBuffer()
    }

    private func flushConsoleBuffer() {
        if let text = consoleBuffer.drain() {
            appendConsoleOutput(text)
        }
    }

    /// Appends text to the console output, capping at ~1 MB to prevent memory bloat.
    func appendConsoleOutput(_ text: String) {
        consoleOutput += text
        if consoleOutput.count > 1_000_000 {
            let startIndex = consoleOutput.index(consoleOutput.startIndex,
                                                  offsetBy: consoleOutput.count - 800_000)
            consoleOutput = "… (earlier output truncated)\n" + String(consoleOutput[startIndex...])
        }
    }
}
