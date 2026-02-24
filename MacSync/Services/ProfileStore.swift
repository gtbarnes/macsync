import Foundation

class ProfileStore {
    private let profilesDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        profilesDirectory = appSupport.appendingPathComponent("MacSync/Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
    }

    func loadProfiles() -> [SyncProfile] {
        let url = profilesDirectory.appendingPathComponent("profiles.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SyncProfile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [SyncProfile]) {
        let url = profilesDirectory.appendingPathComponent("profiles.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
