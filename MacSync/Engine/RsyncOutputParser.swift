import Foundation

enum RsyncOutputParser {

    // MARK: - Itemized Changes Parsing

    /// Parse rsync `--itemize-changes` output into FileAction array.
    ///
    /// Supports both GNU rsync (11-char flags) and macOS openrsync (9-char flags).
    /// Format: `YXcstpoguax path/to/file` (GNU) or `YXcstpogx path/to/file` (openrsync)
    /// - Y = update type: `<` sent (copyRight), `>` received (copyLeft),
    ///   `.` attribute-only/equal, `*` message/deletion, `c` created
    /// - The flags field is followed by a space, then the path.
    static func parseItemizedChanges(_ output: String, syncMode: SyncMode) -> [FileAction] {
        var actions: [FileAction] = []

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Handle deletion lines: `*deleting   path/to/file`
            if trimmed.hasPrefix("*deleting") {
                let path = trimmed
                    .replacingOccurrences(of: "*deleting", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty {
                    actions.append(FileAction(relativePath: path, action: .deleteDest))
                }
                continue
            }

            // Detect flags field dynamically: flags are non-space characters before
            // the first space. This handles both GNU rsync (11 chars) and openrsync (9 chars).
            guard let spaceIndex = trimmed.firstIndex(of: " ") else { continue }
            let flags = String(trimmed[trimmed.startIndex..<spaceIndex])
            let path = String(trimmed[trimmed.index(after: spaceIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Flags must be at least 9 chars (openrsync minimum) and path must exist
            guard flags.count >= 9, !path.isEmpty else { continue }

            let updateType = flags.first ?? "."
            let action: ActionType

            switch updateType {
            case "<":
                // File sent from source to destination
                action = .copyRight
            case ">":
                // File received from destination to source
                action = .copyLeft
            case "c":
                // Created locally (typically copyRight in a one-way sync)
                action = .copyRight
            case ".":
                // Attribute-only change or already equal
                // Check if any change flags are set (after first 2 chars)
                let changeFlags = String(flags.dropFirst(2))
                if changeFlags.allSatisfy({ $0 == "." || $0 == " " }) {
                    action = .equal
                } else {
                    action = .copyRight
                }
            default:
                continue
            }

            actions.append(FileAction(relativePath: path, action: action))
        }

        return actions
    }

    // MARK: - Progress Parsing

    /// Parse rsync `--info=progress2` output line.
    ///
    /// Format: `1,234,567  45%  12.34MB/s  0:01:23`
    /// Returns nil if the line doesn't match the expected format.
    static func parseProgress(_ line: String) -> (bytesTransferred: Int64, percentage: Double, speed: Double, eta: String)? {
        // Match pattern: bytes (with commas)  percentage%  speed  eta
        let pattern = #"^\s*([\d,]+)\s+(\d+)%\s+([\d.]+)(\w+/s)\s+(\d+:\d{2}:\d{2})"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        // Extract bytes (strip commas)
        guard let bytesRange = Range(match.range(at: 1), in: line) else { return nil }
        let bytesString = String(line[bytesRange]).replacingOccurrences(of: ",", with: "")
        guard let bytes = Int64(bytesString) else { return nil }

        // Extract percentage
        guard let percentRange = Range(match.range(at: 2), in: line) else { return nil }
        let percentage = Double(line[percentRange]) ?? 0

        // Extract speed value and unit
        guard let speedValueRange = Range(match.range(at: 3), in: line),
              let speedUnitRange = Range(match.range(at: 4), in: line) else { return nil }
        let speedValue = Double(line[speedValueRange]) ?? 0
        let speedUnit = String(line[speedUnitRange])
        let speed = parseSpeed(value: speedValue, unit: speedUnit)

        // Extract ETA
        guard let etaRange = Range(match.range(at: 5), in: line) else { return nil }
        let eta = String(line[etaRange])

        return (bytes, percentage, speed, eta)
    }

    // MARK: - Speed Unit Parsing

    /// Convert speed value with unit suffix to bytes/second.
    private static func parseSpeed(value: Double, unit: String) -> Double {
        switch unit.lowercased() {
        case "b/s":
            return value
        case "kb/s":
            return value * 1_024
        case "mb/s":
            return value * 1_024 * 1_024
        case "gb/s":
            return value * 1_024 * 1_024 * 1_024
        default:
            return value
        }
    }
}
