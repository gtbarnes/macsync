import Foundation

struct FilterConfig: Codable, Hashable {
    var includePatterns: [String]
    var excludePatterns: [String]

    init() {
        self.includePatterns = []
        self.excludePatterns = [".DS_Store", "Thumbs.db", ".macsync_partial/", "._*"]
    }

    var rsyncFlags: [String] {
        var flags: [String] = []
        for pattern in includePatterns { flags += ["--include", pattern] }
        for pattern in excludePatterns { flags += ["--exclude", pattern] }
        return flags
    }
}
