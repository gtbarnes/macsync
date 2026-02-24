import Foundation

enum SyncMode: String, Codable, CaseIterable, Identifiable {
    case synchronize
    case mirror
    case update

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .synchronize: return "Synchronize"
        case .mirror: return "Mirror"
        case .update: return "Update"
        }
    }
    var description: String {
        switch self {
        case .synchronize: return "Two-way: both sides match, newest wins conflicts"
        case .mirror: return "One-way: destination becomes exact copy of source (deletes included)"
        case .update: return "One-way: copy newer files only, never delete"
        }
    }
    var systemImage: String {
        switch self {
        case .synchronize: return "arrow.left.arrow.right"
        case .mirror: return "arrow.right.square"
        case .update: return "arrow.right"
        }
    }
}

enum DeletionPolicy: Codable, Hashable {
    case trash
    case versioning(path: String)
    case permanent

    var displayName: String {
        switch self {
        case .trash: return "Move to Trash"
        case .versioning: return "Versioning Folder"
        case .permanent: return "Permanent Delete"
        }
    }
}

struct NetworkShareConfig: Codable, Hashable {
    var serverURL: String
    var keychainAccount: String
    var autoReconnect: Bool
    var maxReconnectAttempts: Int
}

struct SyncProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sourcePath: String
    var destinationPath: String
    var syncMode: SyncMode
    var deletionPolicy: DeletionPolicy
    var threadCount: Int
    var filters: FilterConfig
    var rsyncExtraFlags: [String]
    var networkShareConfig: NetworkShareConfig?
    var createdAt: Date
    var lastSyncedAt: Date?

    init(name: String, sourcePath: String, destinationPath: String,
         syncMode: SyncMode = .mirror, deletionPolicy: DeletionPolicy = .trash,
         threadCount: Int = 4) {
        self.id = UUID()
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.syncMode = syncMode
        self.deletionPolicy = deletionPolicy
        self.threadCount = threadCount
        self.filters = FilterConfig()
        self.rsyncExtraFlags = []
        self.networkShareConfig = nil
        self.createdAt = Date()
        self.lastSyncedAt = nil
    }
}
