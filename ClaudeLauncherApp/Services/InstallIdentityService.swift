import Foundation

final class InstallIdentityService {
    private let secretStore: SecretStore
    private let stateStore: AnalyticsStateStore
    private let installIDKey = "analytics.install_id"

    init(secretStore: SecretStore = KeychainService(), stateStore: AnalyticsStateStore = AnalyticsStateStore()) {
        self.secretStore = secretStore
        self.stateStore = stateStore
    }

    func installID() -> String {
        if let existing = secretStore.loadSecret(for: installIDKey), !existing.isEmpty {
            persistMirror(existing)
            return existing
        }

        var state = stateStore.loadState()
        if let mirrored = state.installIDMirror, !mirrored.isEmpty {
            try? secretStore.saveSecret(mirrored, for: installIDKey)
            return mirrored
        }

        let newValue = UUID().uuidString.lowercased()
        try? secretStore.saveSecret(newValue, for: installIDKey)
        state.installIDMirror = newValue
        try? stateStore.saveState(state)
        return newValue
    }

    private func persistMirror(_ value: String) {
        var state = stateStore.loadState()
        guard state.installIDMirror != value else { return }
        state.installIDMirror = value
        try? stateStore.saveState(state)
    }
}
