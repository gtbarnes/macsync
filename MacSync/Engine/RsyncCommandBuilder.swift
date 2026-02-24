import Foundation

struct RsyncCommand {
    let executablePath: String
    let arguments: [String]
    let sourcePath: String
    let destinationPath: String

    var allArguments: [String] {
        arguments + [sourcePath, destinationPath]
    }
}

struct RsyncCommandBuilder {
    let profile: SyncProfile

    // MARK: - Public Build Methods

    /// Build a dry-run preview command with itemized changes output.
    /// Uses `-av` without `-z` (compression is useless in dry-run mode and adds overhead).
    func buildPreviewCommand() -> RsyncCommand {
        var args = ["-av", "--human-readable"]
        args += ["--dry-run", "--itemize-changes"]
        args += modeFlags()
        args += deletionFlags()
        args += filterFlags()
        args += profile.rsyncExtraFlags

        return RsyncCommand(
            executablePath: RsyncBinary.path,
            arguments: args,
            sourcePath: ensureTrailingSlash(profile.sourcePath),
            destinationPath: ensureTrailingSlash(profile.destinationPath)
        )
    }

    /// Build the actual sync command with progress reporting
    func buildSyncCommand() -> RsyncCommand {
        var args = baseFlags()
        args += ["--partial-dir=.macsync_partial", "--info=progress2"]
        args += modeFlags()
        args += deletionFlags()
        args += filterFlags()
        args += profile.rsyncExtraFlags

        return RsyncCommand(
            executablePath: RsyncBinary.path,
            arguments: args,
            sourcePath: ensureTrailingSlash(profile.sourcePath),
            destinationPath: ensureTrailingSlash(profile.destinationPath)
        )
    }

    /// Build a sync command that syncs a subset of files (for parallel execution)
    func buildSyncCommand(filesFrom tempFilePath: String) -> RsyncCommand {
        var args = baseFlags()
        args += ["--partial-dir=.macsync_partial", "--info=progress2"]
        args += ["--files-from=\(tempFilePath)"]
        args += deletionFlags()
        args += filterFlags()
        args += profile.rsyncExtraFlags

        return RsyncCommand(
            executablePath: RsyncBinary.path,
            arguments: args,
            sourcePath: ensureTrailingSlash(profile.sourcePath),
            destinationPath: ensureTrailingSlash(profile.destinationPath)
        )
    }

    // MARK: - Private Helpers

    private func baseFlags() -> [String] {
        ["-avz", "--human-readable"]
    }

    private func modeFlags() -> [String] {
        switch profile.syncMode {
        case .mirror:
            return ["--delete", "--delete-during"]
        case .update:
            return ["--update"]
        case .synchronize:
            // Synchronize mode is handled by the engine running two passes
            // (source->dest then dest->source). No special flags here.
            return []
        }
    }

    private func deletionFlags() -> [String] {
        switch profile.deletionPolicy {
        case .permanent:
            return []
        case .trash:
            let backupDir = NSTemporaryDirectory() + "MacSync_trash_\(UUID().uuidString)"
            return ["--backup", "--backup-dir=\(backupDir)"]
        case .versioning(let path):
            return ["--backup", "--backup-dir=\(path)"]
        }
    }

    private func filterFlags() -> [String] {
        profile.filters.rsyncFlags
    }

    private func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}
