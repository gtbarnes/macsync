import AppKit
import Foundation
import UserNotifications

enum PathRole {
    case source
    case destination
}

final class PermissionService: @unchecked Sendable {
    static let shared = PermissionService()
    private init() {}

    // MARK: - Full Disk Access

    /// Tests whether the app has Full Disk Access by probing a protected path.
    /// Call from a background thread — this performs blocking I/O.
    nonisolated func hasFullDiskAccess() -> Bool {
        let testPath = NSHomeDirectory() + "/Library/Mail"
        return FileManager.default.isReadableFile(atPath: testPath)
    }

    /// Checks if a specific path is accessible for its role.
    /// - Source: must exist and be readable.
    /// - Destination: if it exists, must be writable; if not, parent must be writable.
    /// Returns nil if OK, or an error message.
    /// Call from a background thread — this performs blocking I/O.
    nonisolated func checkPathAccess(_ path: String, role: PathRole) -> String? {
        guard !path.isEmpty else { return "Path is empty" }
        let fm = FileManager.default
        var isDir: ObjCBool = false

        switch role {
        case .source:
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                return "Source path does not exist: \(path)"
            }
            guard fm.isReadableFile(atPath: path) else {
                return "Cannot read source path (permission denied): \(path)"
            }
        case .destination:
            if fm.fileExists(atPath: path, isDirectory: &isDir) {
                guard fm.isWritableFile(atPath: path) else {
                    return "Cannot write to destination (permission denied): \(path)"
                }
            } else {
                let parent = (path as NSString).deletingLastPathComponent
                guard fm.isWritableFile(atPath: parent) else {
                    return "Cannot create destination (parent not writable): \(parent)"
                }
            }
        }
        return nil
    }

    /// Opens System Settings → Full Disk Access pane.
    @MainActor
    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Notifications

    /// Requests notification authorization. Returns true if granted.
    @discardableResult
    func requestNotificationPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // MARK: - First Launch

    private let notificationPermissionRequestedKey = "hasRequestedNotificationPermission"

    /// Runs first-launch permission checks. Returns true if Full Disk Access is available.
    /// Requests notification permission on first launch only.
    func runFirstLaunchChecks() async -> Bool {
        let hasFDA = hasFullDiskAccess()

        let hasRequestedNotifications = UserDefaults.standard.bool(forKey: notificationPermissionRequestedKey)
        if !hasRequestedNotifications {
            UserDefaults.standard.set(true, forKey: notificationPermissionRequestedKey)
            await requestNotificationPermission()
        }

        return hasFDA
    }
}
