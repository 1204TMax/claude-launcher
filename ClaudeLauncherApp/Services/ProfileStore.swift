import Foundation

final class ProfileStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadProfiles() -> [LaunchProfile] {
        let url = storageURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return [LaunchProfile.makeDefault()]
        }

        do {
            let data = try Data(contentsOf: url)
            let profiles = try decoder.decode([LaunchProfile].self, from: data)
            return profiles.isEmpty ? [LaunchProfile.makeDefault()] : profiles
        } catch {
            return [LaunchProfile.makeDefault()]
        }
    }

    func saveProfiles(_ profiles: [LaunchProfile]) throws {
        let url = storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(profiles)
        try data.write(to: url, options: .atomic)
    }

    func exportProfiles(_ profiles: [LaunchProfile], to destination: URL) throws {
        let data = try encoder.encode(profiles)
        try data.write(to: destination, options: .atomic)
    }

    private func storageURL() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("profiles.json")
    }

    func logsDirectory() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("logs", isDirectory: true)
    }

    private func applicationSupportDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeLauncher", isDirectory: true)
    }
}
