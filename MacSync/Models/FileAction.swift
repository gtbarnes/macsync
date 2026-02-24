import Foundation
import SwiftUI

enum ActionType: String, CaseIterable {
    case copyRight
    case copyLeft
    case equal
    case deleteSource
    case deleteDest
    case conflict

    var displayName: String {
        switch self {
        case .copyRight: return "Copy \u{2192}"
        case .copyLeft: return "\u{2190} Copy"
        case .equal: return "Equal"
        case .deleteSource: return "Delete Source"
        case .deleteDest: return "Delete Dest"
        case .conflict: return "Conflict"
        }
    }

    var systemImage: String {
        switch self {
        case .copyRight: return "arrow.right.circle.fill"
        case .copyLeft: return "arrow.left.circle.fill"
        case .equal: return "checkmark.circle"
        case .deleteSource, .deleteDest: return "trash.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .copyRight, .copyLeft: return .green
        case .equal: return .gray
        case .deleteSource, .deleteDest: return .red
        case .conflict: return .orange
        }
    }
}

struct FileAction: Identifiable {
    let id: UUID
    let relativePath: String
    let action: ActionType
    let sourceSize: Int64?
    let destSize: Int64?
    let sourceModified: Date?
    let destModified: Date?
    var excluded: Bool

    init(relativePath: String, action: ActionType,
         sourceSize: Int64? = nil, destSize: Int64? = nil,
         sourceModified: Date? = nil, destModified: Date? = nil) {
        self.id = UUID()
        self.relativePath = relativePath
        self.action = action
        self.sourceSize = sourceSize
        self.destSize = destSize
        self.sourceModified = sourceModified
        self.destModified = destModified
        self.excluded = false
    }

    var fileName: String { (relativePath as NSString).lastPathComponent }
    var directory: String { (relativePath as NSString).deletingLastPathComponent }
}
