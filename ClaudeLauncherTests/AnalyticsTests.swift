import XCTest
@testable import ClaudeLauncher

final class AnalyticsTests: XCTestCase {
    func testTrackAppLifecycleEmitsFirstLaunchOnlyOnce() {
        let stateStore = InMemoryAnalyticsStateStore()
        let queueStore = InMemoryAnalyticsQueueStore()
        let installIdentityService = InstallIdentityService(stateStore: stateStore)
        let analytics = AnalyticsService(
            stateStore: stateStore,
            queueStore: queueStore,
            installIdentityService: installIdentityService,
            transport: FailingAnalyticsTransport(),
            bundle: .testBundle,
            identityDidChange: { _ in },
            collectionEnabledDidChange: { _ in }
        )

        analytics.trackAppLifecycle(profilesCount: 1, storedSessionsCount: 2)
        analytics.trackAppLifecycle(profilesCount: 1, storedSessionsCount: 2)

        let eventNames = queueStore.events.map(\.name)
        XCTAssertEqual(eventNames.filter { $0 == "first_launch" }.count, 1)
        XCTAssertEqual(eventNames.filter { $0 == "app_open" }.count, 2)
    }

    func testSetAnalyticsEnabledFalseStopsTrackingAndClearsQueue() {
        let stateStore = InMemoryAnalyticsStateStore()
        let queueStore = InMemoryAnalyticsQueueStore()
        let analytics = AnalyticsService(
            stateStore: stateStore,
            queueStore: queueStore,
            installIdentityService: InstallIdentityService(stateStore: stateStore),
            transport: NoopAnalyticsTransport(),
            bundle: .testBundle,
            identityDidChange: { _ in },
            collectionEnabledDidChange: { _ in }
        )

        analytics.track(name: "session_launch_requested")
        XCTAssertEqual(queueStore.events.count, 1)

        analytics.setAnalyticsEnabled(false)
        analytics.track(name: "session_launch_succeeded")

        XCTAssertTrue(queueStore.events.isEmpty)
    }

    func testInstallIDRemainsStable() {
        let stateStore = InMemoryAnalyticsStateStore()
        let service = InstallIdentityService(stateStore: stateStore)

        let first = service.installID()
        let second = service.installID()

        XCTAssertEqual(first, second)
        XCTAssertEqual(stateStore.state.installIDMirror, first)
    }
}

private final class InMemoryAnalyticsStateStore: AnalyticsStateStore {
    var state = AnalyticsState()

    override func loadState() -> AnalyticsState {
        state
    }

    override func saveState(_ state: AnalyticsState) throws {
        self.state = state
    }
}

private final class InMemoryAnalyticsQueueStore: AnalyticsQueueStore {
    var events: [AnalyticsEvent] = []

    override func loadEvents() -> [AnalyticsEvent] {
        events
    }

    override func saveEvents(_ events: [AnalyticsEvent]) throws {
        self.events = events
    }
}

private struct FailingAnalyticsTransport: AnalyticsTransport {
    func send(events: [AnalyticsEvent]) throws {
        throw NSError(domain: "AnalyticsTests", code: 1)
    }
}

private extension Bundle {
    static let testBundle = Bundle(for: AnalyticsTests.self)
}
