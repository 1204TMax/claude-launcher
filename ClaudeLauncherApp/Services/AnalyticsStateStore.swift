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
        let url = storageURL()
        guard fileManager.fileExists(atPath: url.path) else {
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

    private func storageURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("analytics-state.json")
    }

    private func applicationSupportDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeLauncher", isDirectory: true)
    }
}
