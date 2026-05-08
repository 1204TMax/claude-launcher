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
        let candidateURLs = [storageURL(appName: "CClauncher"), storageURL(appName: "ClaudeLauncher")]
        guard let url = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
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

    private func storageURL(appName: String = "CClauncher") -> URL {
        applicationSupportDirectory(appName: appName)
            .appendingPathComponent("profiles.json")
    }

    func logsDirectory() -> URL {
        applicationSupportDirectory(appName: "CClauncher")
            .appendingPathComponent("logs", isDirectory: true)
    }

    private func applicationSupportDirectory(appName: String) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }
}
