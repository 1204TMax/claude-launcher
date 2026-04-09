import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [LaunchProfile] = []
    @Published var selectedProfileID: LaunchProfile.ID?
    @Published var sessions: [ManagedSession] = []
    @Published var discoveredSessions: [ManagedSession] = []
    @Published var selectedSessionID: ManagedSession.ID?
    @Published var gateways: [GatewayConfig] = []
    @Published var selectedGatewayID: GatewayConfig.ID?
    @Published var gatewayAPIKeyInput: String = ""
    @Published var commandPreview: String = ""
    @Published var errorMessage: String?
    @Published var launchCountInput: String = "1"

    private let profileStore: ProfileStore
    private let sessionStore: SessionStore
    private let gatewayStore: GatewayStore
    private let keychainService: KeychainService
    private let launchCoordinator: LaunchCoordinator
    private let startupAutomationCoordinator: StartupAutomationCoordinator
    private let discovery: ClaudeSessionDiscovery
    private let sessionMonitor: SessionMonitor

    init(
        profileStore: ProfileStore = ProfileStore(),
        sessionStore: SessionStore = SessionStore(),
        gatewayStore: GatewayStore = GatewayStore(),
        keychainService: KeychainService = KeychainService(),
        launchCoordinator: LaunchCoordinator = LaunchCoordinator(),
        startupAutomationCoordinator: StartupAutomationCoordinator = StartupAutomationCoordinator(),
        discovery: ClaudeSessionDiscovery = ClaudeSessionDiscovery()
    ) {
        self.profileStore = profileStore
        self.sessionStore = sessionStore
        self.gatewayStore = gatewayStore
        self.keychainService = keychainService
        self.launchCoordinator = launchCoordinator
        self.startupAutomationCoordinator = startupAutomationCoordinator
        self.discovery = discovery
        self.sessionMonitor = SessionMonitor(launchCoordinator: launchCoordinator, discovery: discovery)
        self.profiles = profileStore.loadProfiles()
        self.sessions = sessionStore.loadSessions().sorted(by: { $0.updatedAt > $1.updatedAt })
        self.gateways = gatewayStore.loadGateways()
        self.selectedProfileID = profiles.first?.id
        self.selectedSessionID = allSessions.first?.id
        let initialGatewayID = selectedProfile?.gatewayConfigID ?? gateways.first?.id
        self.selectedGatewayID = initialGatewayID
        syncGatewaySelection()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
        startMonitoring()
    }

    deinit {
        sessionMonitor.stop()
    }

    var selectedProfileIndex: Int? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex(where: { $0.id == selectedProfileID })
    }

    var selectedSessionIndex: Int? {
        guard let selectedSessionID else { return nil }
        return allSessions.firstIndex(where: { $0.id == selectedSessionID })
    }

    var selectedGatewayIndex: Int? {
        guard let selectedGatewayID else { return nil }
        return gateways.firstIndex(where: { $0.id == selectedGatewayID })
    }

    var selectedProfile: LaunchProfile? {
        guard let selectedProfileIndex else { return nil }
        return profiles[selectedProfileIndex]
    }

    var selectedSession: ManagedSession? {
        guard let selectedSessionIndex else { return nil }
        return allSessions[selectedSessionIndex]
    }

    var allSessions: [ManagedSession] {
        (sessions + discoveredSessions).sorted(by: stableSessionSort)
    }

    var runningSessionCount: Int {
        allSessions.filter { $0.status == .running }.count
    }

    var idleSessionCount: Int {
        allSessions.filter { $0.status == .idle }.count
    }

    var latestObservedTimeText: String {
        guard let latest = allSessions.compactMap(\ .lastObservedAt).max() else {
            return "未同步"
        }
        let seconds = max(Int(Date().timeIntervalSince(latest)), 0)
        return seconds <= 1 ? "刚刚" : "\(seconds) 秒前"
    }

    var selectedGateway: GatewayConfig? {
        guard let selectedGatewayIndex else { return nil }
        return gateways[selectedGatewayIndex]
    }

    var launchButtonTitle: String {
        "启动 \(resolvedLaunchCount) 个 Claude Code"
    }

    var sessionNamePreview: [String] {
        guard let profile = selectedProfile else { return [] }
        return (1...resolvedLaunchCount).map { profile.resolvedSessionName(index: $0) }
    }

    var sessionNamePreviewText: String {
        sessionNamePreview.joined(separator: "、")
    }

    var gatewayHintText: String {
        "网关切换对新启动会话立即生效；已运行会话不会立刻迁移，需要重启会话。首次未信任目录仍可能出现 Claude 的信任提示。"
    }

    func createProfile() {
        var profile = LaunchProfile.makeDefault()
        profile.name = uniqueProfileName(base: profile.name)
        profile.gatewayConfigID = gateways.first?.id
        profiles.insert(profile, at: 0)
        selectedProfileID = profile.id
        persistProfiles()
        syncGatewaySelection()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func duplicateSelectedProfile() {
        guard var profile = selectedProfile else { return }
        profile.id = UUID()
        profile.name = uniqueProfileName(base: "\(profile.name) 副本")
        profile.createdAt = Date()
        profile.updatedAt = Date()
        profiles.insert(profile, at: 0)
        selectedProfileID = profile.id
        persistProfiles()
        syncGatewaySelection()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func deleteSelectedProfile() {
        guard let selectedProfileIndex else { return }
        profiles.remove(at: selectedProfileIndex)
        if profiles.isEmpty {
            var profile = LaunchProfile.makeDefault()
            profile.gatewayConfigID = gateways.first?.id
            profiles = [profile]
        }
        selectedProfileID = profiles.first?.id
        persistProfiles()
        syncGatewaySelection()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func selectProfile(_ profileID: LaunchProfile.ID?) {
        selectedProfileID = profileID
        syncGatewaySelection()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func selectSession(_ sessionID: ManagedSession.ID?) {
        selectedSessionID = sessionID
    }

    func selectGateway(_ gatewayID: GatewayConfig.ID?) {
        selectedGatewayID = gatewayID
        gatewayAPIKeyInput = selectedGateway.flatMap { keychainService.loadSecret(for: $0.apiKeyReference) } ?? ""
        if let gatewayID {
            updateSelectedProfile { $0.gatewayConfigID = gatewayID }
        }
    }

    func createGateway() {
        let gateway = GatewayConfig.makeDefault()
        gateways.insert(gateway, at: 0)
        selectedGatewayID = gateway.id
        gatewayAPIKeyInput = ""
        persistGateways()
        updateSelectedProfile { $0.gatewayConfigID = gateway.id }
    }

    func deleteSelectedGateway() {
        guard let selectedGatewayIndex else { return }
        let gateway = gateways[selectedGatewayIndex]
        keychainService.deleteSecret(for: gateway.apiKeyReference)
        keychainService.deleteSecret(for: gateway.authTokenReference)
        gateways.remove(at: selectedGatewayIndex)
        if gateways.isEmpty {
            gateways = [GatewayConfig.makeDefault()]
        }
        selectedGatewayID = gateways.first?.id
        gatewayAPIKeyInput = selectedGateway.flatMap { keychainService.loadSecret(for: $0.apiKeyReference) } ?? ""
        let replacementID = gateways.first?.id
        for index in profiles.indices where profiles[index].gatewayConfigID == gateway.id {
            profiles[index].gatewayConfigID = replacementID
        }
        persistGateways()
        persistProfiles()
        refreshPreview()
    }

    func updateSelectedGateway(_ mutate: (inout GatewayConfig) -> Void) {
        guard let selectedGatewayIndex else { return }
        mutate(&gateways[selectedGatewayIndex])
        gateways[selectedGatewayIndex].updatedAt = Date()
        persistGateways()
        refreshPreview()
    }

    func updateGatewayAPIKey(_ value: String) {
        gatewayAPIKeyInput = value
        guard let gateway = selectedGateway else { return }
        do {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                keychainService.deleteSecret(for: gateway.apiKeyReference)
            } else {
                try keychainService.saveSecret(value, for: gateway.apiKeyReference)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSelectedProfile(_ mutate: (inout LaunchProfile) -> Void) {
        guard let selectedProfileIndex else { return }
        mutate(&profiles[selectedProfileIndex])
        profiles[selectedProfileIndex].updatedAt = Date()
        persistProfiles()
        refreshPreview()
    }

    func updateLaunchCountInput(_ value: String) {
        let filtered = value.filter(\.isNumber)
        launchCountInput = filtered
        if let count = Int(filtered), count >= 1 {
            updateSelectedProfile { $0.batchCount = count }
        } else {
            refreshPreview()
        }
    }

    func increaseLaunchCount() {
        updateLaunchCountInput(String(min(resolvedLaunchCount + 1, 99)))
    }

    func decreaseLaunchCount() {
        updateLaunchCountInput(String(max(resolvedLaunchCount - 1, 1)))
    }

    func browseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            updateSelectedProfile { $0.workingDirectory = url.path }
        }
    }

    func launchSelectedProfile() {
        guard let profile = selectedProfile else { return }
        let launchProfile = profileWithResolvedBatchCount(profile)
        let selectedGateway = gateways.first(where: { $0.id == launchProfile.gatewayConfigID })
        let gatewaySecret = selectedGateway.flatMap { keychainService.loadSecret(for: $0.apiKeyReference) }

        if let error = launchCoordinator.validate(profile: launchProfile) {
            errorMessage = error
            return
        }

        errorMessage = nil
        let preparations = launchCoordinator.prepareLaunches(for: launchProfile, gateway: selectedGateway, apiKey: gatewaySecret)
        for preparation in preparations {
            let automationPlan = startupAutomationCoordinator.makePlan(for: launchProfile, sessionName: preparation.sessionName)
            do {
                let launchResult = try launchCoordinator.launchInTerminal(preparation)
                let matchedDiscovered = discovery.discoverLiveSessions().first(where: { ($0.name ?? "") == preparation.sessionName || $0.cwd == launchProfile.workingDirectory })
                let session = ManagedSession.make(
                    origin: .appLaunched,
                    profile: launchProfile,
                    gatewayName: selectedGateway?.name,
                    displayName: preparation.sessionName,
                    command: preparation.shellCommand,
                    status: .running,
                    claudeSessionID: matchedDiscovered?.sessionID,
                    pid: matchedDiscovered?.pid,
                    terminalWindowID: launchResult.windowID,
                    terminalTabIndex: launchResult.tabIndex,
                    summary: automationPlan.summaryPlaceholder,
                    summaryStatus: .placeholder,
                    canSendCommands: true,
                    canTerminate: true,
                    renameCommandTemplate: "/rename {name}"
                )
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
            } catch {
                let session = ManagedSession.make(
                    origin: .appLaunched,
                    profile: launchProfile,
                    gatewayName: selectedGateway?.name,
                    displayName: preparation.sessionName,
                    command: preparation.shellCommand,
                    status: .failed,
                    errorMessage: error.localizedDescription,
                    summary: automationPlan.summaryPlaceholder,
                    summaryStatus: .placeholder,
                    canSendCommands: false,
                    canTerminate: false
                )
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
                errorMessage = error.localizedDescription
            }
        }
        persistSessions()
    }

    func updateSelectedSessionName(_ name: String) {
        guard let session = selectedSession else { return }
        let renameCommand = "/rename \(name.nonEmpty(or: session.launchedName))"

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            let newName = name.nonEmpty(or: sessions[index].launchedName)
            sessions[index].displayName = newName

            var syncSucceeded = false
            if let windowID = sessions[index].terminalWindowID,
               let tabIndex = sessions[index].terminalTabIndex,
               sessions[index].status == .running || sessions[index].status == .idle {
                do {
                    try launchCoordinator.sendCommand(renameCommand, toWindowID: windowID, tabIndex: tabIndex)
                    syncSucceeded = true
                } catch {
                    sessions[index].errorMessage = "改名同步失败：\(error.localizedDescription)"
                }
            }

            if !syncSucceeded, let pid = sessions[index].pid {
                syncSucceeded = launchCoordinator.sendCommandToProcessTTY(command: renameCommand, pid: pid)
            }

            if syncSucceeded {
                sessions[index].claudeSessionName = newName
                sessions[index].errorMessage = nil
            } else {
                sessions[index].errorMessage = "改名未同步到 Claude。"
                errorMessage = sessions[index].errorMessage
            }

            touchManagedSession(at: index)
            return
        }

        if let index = discoveredSessions.firstIndex(where: { $0.id == session.id }) {
            let newName = name.nonEmpty(or: discoveredSessions[index].launchedName)
            discoveredSessions[index].displayName = newName
            if let pid = discoveredSessions[index].pid,
               launchCoordinator.sendCommandToProcessTTY(command: renameCommand, pid: pid) {
                discoveredSessions[index].claudeSessionName = newName
                discoveredSessions[index].errorMessage = nil
            } else {
                discoveredSessions[index].errorMessage = "改名未同步到 Claude。"
                errorMessage = discoveredSessions[index].errorMessage
            }
            return
        }
    }

    func updateSelectedSessionNotes(_ notes: String) {
        guard let session = selectedSession else { return }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].notes = notes
            touchManagedSession(at: index)
        }
    }

    func generateSummaryPlaceholder() {
        guard let session = selectedSession else { return }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            let managedSession = sessions[index]
            sessions[index].summary = "基于配置「\(managedSession.profileName)」启动，当前会话名为「\(managedSession.displayName)」，等待补充对话摘要。"
            sessions[index].summaryStatus = .placeholder
            touchManagedSession(at: index)
        }
    }

    func archiveSelectedSession() {
        guard let session = selectedSession else { return }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].status = .archived
            touchManagedSession(at: index)
        }
    }

    func terminateSelectedSession() {
        guard let session = selectedSession else { return }
        guard session.canTerminate, let pid = session.pid else {
            errorMessage = "当前会话无法从应用内关闭。"
            return
        }

        if launchCoordinator.terminateProcess(pid: pid) {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index].status = .exited
                touchManagedSession(at: index)
            }
            if let discoveredIndex = discoveredSessions.firstIndex(where: { $0.id == session.id }) {
                discoveredSessions[discoveredIndex].status = .exited
            }
        } else {
            errorMessage = "关闭会话失败。"
        }
    }

    func refreshPreview() {
        guard let profile = selectedProfile else {
            commandPreview = ""
            return
        }
        let previewProfile = profileWithResolvedBatchCount(profile)
        let gateway = gateways.first(where: { $0.id == previewProfile.gatewayConfigID })
        let apiKey = gateway.flatMap { keychainService.loadSecret(for: $0.apiKeyReference) }
        commandPreview = launchCoordinator.prepareLaunches(for: previewProfile, gateway: gateway, apiKey: apiKey).first?.shellCommand ?? ""
    }

    var resolvedLaunchCount: Int {
        if let count = Int(launchCountInput), count >= 1 {
            return count
        }
        return max(selectedProfile?.batchCount ?? 1, 1)
    }

    private func profileWithResolvedBatchCount(_ profile: LaunchProfile) -> LaunchProfile {
        var copy = profile
        copy.batchCount = resolvedLaunchCount
        return copy
    }

    private func syncLaunchCountInputFromSelectedProfile() {
        launchCountInput = String(max(selectedProfile?.batchCount ?? 1, 1))
    }

    private func syncGatewaySelection() {
        selectedGatewayID = selectedProfile?.gatewayConfigID ?? gateways.first?.id
        gatewayAPIKeyInput = selectedGateway.flatMap { keychainService.loadSecret(for: $0.apiKeyReference) } ?? ""
    }

    private func touchManagedSession(at index: Int) {
        let now = Date()
        sessions[index].updatedAt = now
        sessions[index].lastActivityAt = now
        persistSessions()
    }

    private func persistProfiles() {
        do {
            try profileStore.saveProfiles(profiles)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSessions() {
        do {
            try sessionStore.saveSessions(sessions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistGateways() {
        do {
            try gatewayStore.saveGateways(gateways)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startMonitoring() {
        sessionMonitor.start(onTick: { [weak self] discovered, states in
            self?.applyMonitoring(discovered: discovered, terminalStates: states)
        }, sessionsProvider: { [weak self] in
            self?.sessions ?? []
        })
    }

    private func applyMonitoring(discovered: [DiscoveredClaudeSession], terminalStates: [UUID: MonitoredTerminalState]) {
        let now = Date()
        mergeDiscoveredSessions(discovered, now: now)
        applyMonitoredStates(terminalStates, now: now)
        pruneClosedManagedSessions(now: now)
    }

    private func mergeDiscoveredSessions(_ discovered: [DiscoveredClaudeSession], now: Date) {
        var external: [ManagedSession] = []
        let unnamedDiscovered = discovered
            .filter { $0.normalizedName == nil }
            .sorted { lhs, rhs in
                if let l = lhs.startedAt, let r = rhs.startedAt, l != r { return l < r }
                return lhs.pid < rhs.pid
            }
        let unnamedIndexMap = Dictionary(uniqueKeysWithValues: unnamedDiscovered.enumerated().map { offset, session in
            (session.id, "未命名 \(offset + 1)")
        })

        for discoveredSession in discovered {
            let metadataName = discoveredSession.normalizedName
            let fallbackName = unnamedIndexMap[discoveredSession.id] ?? "未命名"

            if let managedIndex = sessions.firstIndex(where: {
                ($0.claudeSessionID != nil && $0.claudeSessionID == discoveredSession.sessionID) ||
                ($0.pid != nil && $0.pid == discoveredSession.pid)
            }) {
                let oldClaudeName = sessions[managedIndex].claudeSessionName
                sessions[managedIndex].pid = discoveredSession.pid
                sessions[managedIndex].claudeSessionID = discoveredSession.sessionID
                sessions[managedIndex].lastObservedAt = now
                if let metadataName {
                    sessions[managedIndex].claudeSessionName = metadataName
                    let currentDisplayName = sessions[managedIndex].displayName
                    if currentDisplayName == sessions[managedIndex].launchedName || currentDisplayName == oldClaudeName || currentDisplayName.hasPrefix("未命名 ") {
                        sessions[managedIndex].displayName = metadataName
                    }
                } else if sessions[managedIndex].origin == .discoveredExternal && sessions[managedIndex].displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sessions[managedIndex].displayName = fallbackName
                }
                if sessions[managedIndex].status != .archived && sessions[managedIndex].status != .failed {
                    sessions[managedIndex].status = .running
                }
                continue
            }

            let discoveredName = metadataName ?? fallbackName
            let stableID = sessions.first(where: {
                ($0.claudeSessionID != nil && $0.claudeSessionID == discoveredSession.sessionID) ||
                ($0.pid != nil && $0.pid == discoveredSession.pid)
            })?.id ?? discoveredSessions.first(where: {
                ($0.claudeSessionID != nil && $0.claudeSessionID == discoveredSession.sessionID) ||
                ($0.pid != nil && $0.pid == discoveredSession.pid)
            })?.id ?? UUID()

            let session = ManagedSession.make(
                id: stableID,
                origin: .discoveredExternal,
                profile: nil,
                gatewayName: nil,
                displayName: discoveredName,
                command: "claude (外部发现)",
                status: .running,
                claudeSessionID: discoveredSession.sessionID,
                pid: discoveredSession.pid,
                summary: "外部发现的实时 Claude Code 会话。",
                summaryStatus: .placeholder,
                canSendCommands: true,
                canTerminate: true,
                renameCommandTemplate: "/rename {name}",
                createdAt: discoveredSession.startedAt ?? now
            )
            var enriched = session
            enriched.workingDirectory = discoveredSession.cwd
            enriched.lastObservedAt = now
            enriched.claudeSessionName = metadataName
            external.append(enriched)
        }

        discoveredSessions = external
        persistSessions()
    }

    private func applyMonitoredStates(_ states: [UUID: MonitoredTerminalState], now: Date) {
        var didChange = false

        for index in sessions.indices {
            if let pid = sessions[index].pid,
               !discoveredSessions.contains(where: { $0.pid == pid }) {
                if sessions[index].status != .archived && sessions[index].status != .failed {
                    sessions[index].status = .exited
                    sessions[index].updatedAt = now
                    didChange = true
                }
            }

            let sessionID = sessions[index].id
            guard let state = states[sessionID] else { continue }
            sessions[index].lastObservedAt = now

            let newStatus: ManagedSessionStatus
            if !state.exists {
                newStatus = .exited
            } else if state.isBusy {
                newStatus = .running
            } else {
                newStatus = .idle
            }

            if sessions[index].status != newStatus {
                sessions[index].status = newStatus
                sessions[index].updatedAt = now
                didChange = true
            }
        }

        if didChange {
            persistSessions()
        }
    }

    private func pruneClosedManagedSessions(now: Date) {
        let livePIDs = Set(discoveredSessions.compactMap { $0.pid })
        let removedIDs = Set(sessions.compactMap { session -> UUID? in
            guard session.origin == .appLaunched else { return nil }
            guard session.status != .archived && session.status != .failed else { return nil }
            if session.status == .exited {
                return session.id
            }
            if let pid = session.pid, !livePIDs.contains(pid) {
                return session.id
            }
            return nil
        })

        sessions.removeAll { removedIDs.contains($0.id) }

        if let selectedSessionID, removedIDs.contains(selectedSessionID) {
            self.selectedSessionID = allSessions.first?.id
        }

        persistSessions()
    }

    private func stableSessionSort(lhs: ManagedSession, rhs: ManagedSession) -> Bool {
        let rank: (ManagedSessionStatus) -> Int = {
            switch $0 {
            case .running: 0
            case .idle: 1
            case .launching: 2
            case .failed: 3
            case .archived: 4
            case .exited: 5
            }
        }
        let leftRank = rank(lhs.status)
        let rightRank = rank(rhs.status)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if lhs.lastObservedAt != rhs.lastObservedAt {
            return (lhs.lastObservedAt ?? lhs.createdAt) > (rhs.lastObservedAt ?? rhs.createdAt)
        }
        return lhs.createdAt > rhs.createdAt
    }

    private func uniqueProfileName(base: String) -> String {
        var candidate = base
        var index = 2
        while profiles.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(index)"
            index += 1
        }
        return candidate
    }
}
