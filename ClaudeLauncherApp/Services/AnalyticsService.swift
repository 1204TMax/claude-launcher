import Foundation

protocol AnalyticsTransport {
    func send(events: [AnalyticsEvent]) throws
}

struct NoopAnalyticsTransport: AnalyticsTransport {
    func send(events: [AnalyticsEvent]) throws {}
}

final class AnalyticsService {
    private let stateStore: AnalyticsStateStore
    private let queueStore: AnalyticsQueueStore
    private let installIdentityService: InstallIdentityService
    private let transport: AnalyticsTransport
    private let bundle: Bundle
    private let identityDidChange: (String) -> Void
    private let collectionEnabledDidChange: (Bool) -> Void
    private var state: AnalyticsState
    private var queuedEvents: [AnalyticsEvent]

    init(
        stateStore: AnalyticsStateStore = AnalyticsStateStore(),
        queueStore: AnalyticsQueueStore = AnalyticsQueueStore(),
        installIdentityService: InstallIdentityService = InstallIdentityService(),
        transport: AnalyticsTransport = NoopAnalyticsTransport(),
        bundle: Bundle = .main,
        identityDidChange: @escaping (String) -> Void = { _ in },
        collectionEnabledDidChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.stateStore = stateStore
        self.queueStore = queueStore
        self.installIdentityService = installIdentityService
        self.transport = transport
        self.bundle = bundle
        self.identityDidChange = identityDidChange
        self.collectionEnabledDidChange = collectionEnabledDidChange
        var loadedState = stateStore.loadState()
        if !loadedState.analyticsEnabled {
            loadedState.analyticsEnabled = true
        }
        self.state = loadedState
        self.queuedEvents = queueStore.loadEvents()
        let installID = installIdentityService.installID()
        self.identityDidChange(installID)
        self.collectionEnabledDidChange(self.state.analyticsEnabled)
        persistState()
    }

    func trackAppLifecycle(profilesCount: Int, storedSessionsCount: Int) {
        let now = Date()
        let properties = baseProperties().merging([
            "profiles_count": String(profilesCount),
            "stored_sessions_count": String(storedSessionsCount)
        ]) { _, new in new }

        if state.firstLaunchAt == nil {
            state.firstLaunchAt = now
            enqueue(name: "first_launch", properties: properties)
        }

        state.lastAppOpenAt = now
        enqueue(name: "app_open", properties: properties)
        persistState()
        flushIfNeeded(force: true)
    }

    func track(name: String, properties: [String: String] = [:], flushImmediately: Bool = false) {
        guard state.analyticsEnabled else { return }
        enqueue(name: name, properties: properties)
        flushIfNeeded(force: flushImmediately)
    }

    func setAnalyticsEnabled(_ enabled: Bool) {
        state.analyticsEnabled = enabled
        collectionEnabledDidChange(enabled)
        if !enabled {
            queuedEvents = []
            try? queueStore.saveEvents([])
        }
        persistState()
    }

    private func enqueue(name: String, properties: [String: String]) {
        guard state.analyticsEnabled else { return }
        let event = AnalyticsEvent(name: name, properties: baseProperties().merging(properties) { _, new in new })
        queuedEvents.append(event)
        try? queueStore.saveEvents(queuedEvents)
        persistState()
    }

    private func flushIfNeeded(force: Bool) {
        guard state.analyticsEnabled else { return }
        guard force || queuedEvents.count >= 20 else { return }
        do {
            try transport.send(events: queuedEvents)
            queuedEvents = []
            try queueStore.saveEvents([])
        } catch {
            try? queueStore.saveEvents(queuedEvents)
        }
    }

    private func persistState() {
        try? stateStore.saveState(state)
    }

    private func baseProperties() -> [String: String] {
        [
            "install_id": installIdentityService.installID(),
            "app_version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build_number": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "macos_version": ProcessInfo.processInfo.operatingSystemVersionString
        ]
    }
}
