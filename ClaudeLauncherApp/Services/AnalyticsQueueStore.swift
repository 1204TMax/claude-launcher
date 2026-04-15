import Foundation

class AnalyticsQueueStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let maxEventCount: Int

    init(fileManager: FileManager = .default, maxEventCount: Int = 500) {
        self.fileManager = fileManager
        self.maxEventCount = maxEventCount
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadEvents() -> [AnalyticsEvent] {
        let url = storageURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([AnalyticsEvent].self, from: data)
        } catch {
            return []
        }
    }

    func saveEvents(_ events: [AnalyticsEvent]) throws {
        let url = storageURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let trimmedEvents = Array(events.suffix(maxEventCount))
        let data = try encoder.encode(trimmedEvents)
        try data.write(to: url, options: .atomic)
    }

    private func storageURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("analytics-queue.json")
    }

    private func applicationSupportDirectory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeLauncher", isDirectory: true)
    }
}
