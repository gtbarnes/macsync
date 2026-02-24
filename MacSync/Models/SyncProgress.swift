import Foundation

struct SyncProgress {
    var totalFiles: Int = 0
    var completedFiles: Int = 0
    var totalBytes: Int64 = 0
    var transferredBytes: Int64 = 0
    var currentSpeed: Double = 0
    var smoothedSpeed: Double = 0
    var startTime: Date?
    var currentFile: String = ""

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    var eta: TimeInterval? {
        guard smoothedSpeed > 0 else { return nil }
        return Double(totalBytes - transferredBytes) / smoothedSpeed
    }

    var etaFormatted: String {
        guard let eta = eta else { return "--:--" }
        let h = Int(eta) / 3600; let m = (Int(eta) % 3600) / 60; let s = Int(eta) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var speedFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(smoothedSpeed), countStyle: .file) + "/s"
    }
}

enum TaskPhase: String {
    case idle, comparing, previewing, syncing, paused, completed, failed
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .comparing: return "Comparing\u{2026}"
        case .previewing: return "Preview Ready"
        case .syncing: return "Syncing\u{2026}"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    var isActive: Bool { self == .comparing || self == .syncing }
}

enum Bottleneck: String {
    case none, disk, network, cpu
    var displayName: String {
        switch self {
        case .none: return "None"; case .disk: return "Disk I/O"
        case .network: return "Network"; case .cpu: return "CPU"
        }
    }
}

struct DiagnosticState {
    var bottleneck: Bottleneck = .none
    var diskReadSpeed: Double = 0
    var diskWriteSpeed: Double = 0
    var networkSpeed: Double = 0
    var activeThreads: Int = 0
}
