import Foundation

enum RsyncBinary {
    static var path: String {
        // 1. Bundled in app
        if let bundled = Bundle.main.path(forResource: "rsync", ofType: nil) {
            return bundled
        }
        // 2. Homebrew Apple Silicon
        let homebrew = "/opt/homebrew/bin/rsync"
        if FileManager.default.isExecutableFile(atPath: homebrew) { return homebrew }
        // 3. Homebrew Intel
        let intel = "/usr/local/bin/rsync"
        if FileManager.default.isExecutableFile(atPath: intel) { return intel }
        // 4. System fallback
        return "/usr/bin/rsync"
    }

    static var version: String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.components(separatedBy: "\n").first ?? "unknown"
    }
}
