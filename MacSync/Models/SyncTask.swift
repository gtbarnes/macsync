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
    var comparisonStartTime: Date?
    var rsyncProcesses: [Process] = []
    var isCancelled: Bool = false

    init(profile: SyncProfile) {
        self.id = UUID()
        self.profile = profile
    }
}
