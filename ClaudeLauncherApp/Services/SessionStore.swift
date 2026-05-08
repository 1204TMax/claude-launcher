import Foundation

final class SessionStore {
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

    func loadSessions() -> [ManagedSession] {
        let candidateURLs = [sessionsStorageURL(appName: "CClauncher"), sessionsStorageURL(appName: "ClaudeLauncher")]
        guard let url = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([ManagedSession].self, from: data)
        } catch {
            return []
        }
    }

    func saveSessions(_ sessions: [ManagedSession]) throws {
        let url = sessionsStorageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(sessions)
        try data.write(to: url, options: .atomic)
    }

    func loadDiscoveredSessionMetadata() -> [String: DiscoveredSessionMetadata] {
        let candidateURLs = [discoveredSessionMetadataStorageURL(appName: "CClauncher"), discoveredSessionMetadataStorageURL(appName: "ClaudeLauncher")]
        guard let url = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([String: DiscoveredSessionMetadata].self, from: data)
        } catch {
            return [:]
        }
    }

    func saveDiscoveredSessionMetadata(_ metadata: [String: DiscoveredSessionMetadata]) throws {
        let url = discoveredSessionMetadataStorageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }

    private func baseStorageURL(appName: String = "CClauncher") -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    private func sessionsStorageURL(appName: String = "CClauncher") -> URL {
        baseStorageURL(appName: appName).appendingPathComponent("sessions.json")
    }

    private func discoveredSessionMetadataStorageURL(appName: String = "CClauncher") -> URL {
        baseStorageURL(appName: appName).appendingPathComponent("discovered-session-metadata.json")
    }
}
