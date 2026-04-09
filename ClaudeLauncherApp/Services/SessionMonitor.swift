import Foundation

final class SessionMonitor {
    private let launchCoordinator: LaunchCoordinator
    private let discovery: ClaudeSessionDiscovery
    private var timer: Timer?

    init(launchCoordinator: LaunchCoordinator, discovery: ClaudeSessionDiscovery) {
        self.launchCoordinator = launchCoordinator
        self.discovery = discovery
    }

    func start(interval: TimeInterval = 3, onTick: @escaping @MainActor ([DiscoveredClaudeSession], [UUID: MonitoredTerminalState]) -> Void, sessionsProvider: @escaping @MainActor () -> [ManagedSession]) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                let sessions = sessionsProvider()
                let discovered = self.discovery.discoverLiveSessions()
                var result: [UUID: MonitoredTerminalState] = [:]
                for session in sessions {
                    guard let windowID = session.terminalWindowID, let tabIndex = session.terminalTabIndex else { continue }
                    if session.status == .archived || session.status == .failed || session.status == .exited { continue }
                    if let state = try? self.launchCoordinator.fetchTerminalState(windowID: windowID, tabIndex: tabIndex) {
                        result[session.id] = state
                    }
                }
                onTick(discovered, result)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
