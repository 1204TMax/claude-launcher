import Foundation

class AnalyticsStateStore {
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

    func loadState() -> AnalyticsState {
        let candidateURLs = [storageURL(appName: "CClauncher"), storageURL(appName: "ClaudeLauncher")]
        guard let url = candidateURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return AnalyticsState()
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(AnalyticsState.self, from: data)
        } catch {
            return AnalyticsState()
        }
    }

    func saveState(_ state: AnalyticsState) throws {
        let url = storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private func storageURL(appName: String = "CClauncher") -> URL {
        applicationSupportDirectory(appName: appName).appendingPathComponent("analytics-state.json")
    }

    private func applicationSupportDirectory(appName: String) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appName, isDirectory: true)
    }
}
