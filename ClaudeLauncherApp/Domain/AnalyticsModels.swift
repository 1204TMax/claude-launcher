import Foundation

struct AnalyticsEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let occurredAt: Date
    let properties: [String: String]

    init(id: UUID = UUID(), name: String, occurredAt: Date = Date(), properties: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.occurredAt = occurredAt
        self.properties = properties
    }
}

struct AnalyticsState: Codable, Equatable {
    var analyticsEnabled: Bool
    var firstLaunchAt: Date?
    var lastAppOpenAt: Date?
    var installIDMirror: String?

    init(
        analyticsEnabled: Bool = true,
        firstLaunchAt: Date? = nil,
        lastAppOpenAt: Date? = nil,
        installIDMirror: String? = nil
    ) {
        self.analyticsEnabled = analyticsEnabled
        self.firstLaunchAt = firstLaunchAt
        self.lastAppOpenAt = lastAppOpenAt
        self.installIDMirror = installIDMirror
    }
}
