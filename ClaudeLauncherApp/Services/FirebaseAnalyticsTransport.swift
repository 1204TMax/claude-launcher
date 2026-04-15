import Foundation
import FirebaseAnalytics

struct FirebaseAnalyticsTransport: AnalyticsTransport {
    func send(events: [AnalyticsEvent]) throws {
        for event in events {
            Analytics.logEvent(normalizedEventName(event.name), parameters: normalizedParameters(event.properties))
        }
    }

    static func configureIdentity(installID: String) {
        Analytics.setUserID(installID)
        Analytics.setUserProperty(installID, forName: "install_id")
    }

    static func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    private func normalizedEventName(_ value: String) -> String {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)
        let collapsed = normalized.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let fallback = trimmed.isEmpty ? "app_event" : trimmed
        return String(fallback.prefix(40))
    }

    private func normalizedParameters(_ parameters: [String: String]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in parameters {
            let normalizedKey = normalizedParameterName(key)
            guard !normalizedKey.isEmpty else { continue }
            result[normalizedKey] = String(value.prefix(100))
        }
        return result
    }

    private func normalizedParameterName(_ value: String) -> String {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_]", with: "_", options: .regularExpression)
        let collapsed = normalized.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let fallback = trimmed.isEmpty ? "param" : trimmed
        return String(fallback.prefix(40))
    }
}
