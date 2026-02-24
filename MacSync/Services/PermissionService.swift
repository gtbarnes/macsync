import AppKit
import Foundation
import UserNotifications

@MainActor
final class PermissionService {
    static let shared = PermissionService()
    private init() {}

    // MARK: - Full Disk Access

    /// Tests whether the app has Full Disk Access by probing a protected path.
    func hasFullDiskAccess() -> Bool {
        let testPath = NSHomeDirectory() + "/Library/Mail"
        return FileManager.default.isReadableFile(atPath: testPath)
    }

    /// Checks if a specific path is readable. Returns nil if OK, or an error message.
    func checkPathAccess(_ path: String) -> String? {
        guard !path.isEmpty else { return "Path is empty" }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return "Path does not exist: \(path)"
        }
        guard fm.isReadableFile(atPath: path) else {
            return "Cannot read path (permission denied): \(path)"
        }
        return nil
    }

    /// Opens System Settings → Full Disk Access pane.
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

    /// Runs first-launch permission checks. Returns true if Full Disk Access is available.
    func runFirstLaunchChecks() async -> Bool {
        let hasChecked = UserDefaults.standard.bool(forKey: "hasCheckedFullDiskAccess")
        let hasFDA = hasFullDiskAccess()

        if !hasChecked {
            UserDefaults.standard.set(true, forKey: "hasCheckedFullDiskAccess")
            await requestNotificationPermission()
        }

        return hasFDA
    }
}
