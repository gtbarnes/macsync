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
    @Published var lastScannedPath: String?
    @Published var consoleOutput: String = ""
    var comparisonStartTime: Date?
    var rsyncProcesses: [Process] = []
    var isCancelled: Bool = false

    /// Appends raw text to the console output, capping at ~1 MB to prevent memory bloat.
    func appendConsoleOutput(_ text: String) {
        consoleOutput += text
        if consoleOutput.count > 1_000_000 {
            let startIndex = consoleOutput.index(consoleOutput.startIndex,
                                                  offsetBy: consoleOutput.count - 800_000)
            consoleOutput = "… (earlier output truncated)\n" + String(consoleOutput[startIndex...])
        }
    }

    init(profile: SyncProfile) {
        self.id = UUID()
        self.profile = profile
    }
}
