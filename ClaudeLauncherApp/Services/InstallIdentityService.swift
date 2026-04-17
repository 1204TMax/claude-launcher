import Foundation

final class InstallIdentityService {
    private let stateStore: AnalyticsStateStore

    init(stateStore: AnalyticsStateStore = AnalyticsStateStore()) {
        self.stateStore = stateStore
    }

    func installID() -> String {
        let state = stateStore.loadState()
        if let existing = state.installIDMirror, !existing.isEmpty {
            return existing
        }

        let newValue = UUID().uuidString.lowercased()
        persistInstallID(newValue)
        return newValue
    }

    private func persistInstallID(_ value: String) {
        var state = stateStore.loadState()
        guard state.installIDMirror != value else { return }
        state.installIDMirror = value
        try? stateStore.saveState(state)
    }
}
