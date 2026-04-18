import AppKit
import Foundation
import SwiftUI

struct SessionListItem: Identifiable, Equatable {
    enum Source: Equatable {
        case managed(ManagedSession.ID)
        case discovered(String)
    }

    let id: String
    let source: Source
    let title: String
    let sessionID: String?
    let cwd: String
    let lastActivityAt: Date
    let isPinned: Bool
    let isLive: Bool
    let isClosed: Bool
    let statusText: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [LaunchProfile] = []
    @Published var selectedProfileID: LaunchProfile.ID?
    @Published var sessions: [ManagedSession] = []
    @Published var selectedSessionID: ManagedSession.ID?
    @Published var commandPreview: String = ""
    @Published var errorMessage: String?
    @Published var launchCountInput: String = "1"
    @Published var discoveredSessions: [ClaudeTranscriptSession] = []
    @Published var selectedDiscoveredSessionID: String?
    @Published var selectedTranscriptMessages: [ClaudeTranscriptMessage] = []
    @Published var discoveredSessionMetadata: [String: DiscoveredSessionMetadata] = [:]
    @Published var profileSaveStatus: ProfileSaveStatus = .idle
    @Published var isDiscoveringSessions: Bool = false

    private var allTranscriptMessages: [ClaudeTranscriptMessage] = []
    private var transcriptDisplayCount: Int = 0
    private let transcriptPageSize: Int = 80

    private let profileStore: ProfileStore
    private let sessionStore: SessionStore
    private let launchCoordinator: LaunchCoordinator
    private let startupAutomationCoordinator: StartupAutomationCoordinator
    private let claudeSessionDiscovery: ClaudeSessionDiscovery
    private let analyticsService: AnalyticsService
    private let profilePersistenceQueue = DispatchQueue(label: "ClaudeLauncher.ProfilePersistence", qos: .utility)
    private let sessionDiscoveryQueue = DispatchQueue(label: "ClaudeLauncher.SessionDiscovery", qos: .utility)
    private var sessionDiscoveryGeneration = 0
    private var transcriptLoadGeneration = 0

    init(
        profileStore: ProfileStore = ProfileStore(),
        sessionStore: SessionStore = SessionStore(),
        launchCoordinator: LaunchCoordinator = LaunchCoordinator(),
        startupAutomationCoordinator: StartupAutomationCoordinator = StartupAutomationCoordinator(),
        claudeSessionDiscovery: ClaudeSessionDiscovery = ClaudeSessionDiscovery(),
        analyticsService: AnalyticsService = AnalyticsService()
    ) {
        self.profileStore = profileStore
        self.sessionStore = sessionStore
        self.launchCoordinator = launchCoordinator
        self.startupAutomationCoordinator = startupAutomationCoordinator
        self.claudeSessionDiscovery = claudeSessionDiscovery
        self.analyticsService = analyticsService
        self.profiles = profileStore.loadProfiles()
        self.sessions = sessionStore.loadSessions().sorted(by: stableSessionSort)
        self.discoveredSessionMetadata = sessionStore.loadDiscoveredSessionMetadata()
        self.selectedProfileID = profiles.first?.id
        self.selectedSessionID = sessions.first?.id
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
        analyticsService.trackAppLifecycle(
            profilesCount: profiles.count,
            storedSessionsCount: sessions.count
        )
        reloadDiscoveredSessions()
    }

    var selectedProfileIndex: Int? {
        guard let selectedProfileID else { return nil }
        return profiles.firstIndex(where: { $0.id == selectedProfileID })
    }

    var selectedSessionIndex: Int? {
        guard let selectedSessionID else { return nil }
        return sessions.firstIndex(where: { $0.id == selectedSessionID })
    }

    var selectedProfile: LaunchProfile? {
        guard let selectedProfileIndex else { return nil }
        return profiles[selectedProfileIndex]
    }

    var selectedSession: ManagedSession? {
        guard let selectedSessionIndex else { return nil }
        return sessions[selectedSessionIndex]
    }

    var selectedDiscoveredSession: ClaudeTranscriptSession? {
        guard let selectedDiscoveredSessionID else { return nil }
        return discoveredSessions.first { $0.id == selectedDiscoveredSessionID }
    }

    var sessionListItems: [SessionListItem] {
        discoveredSessions.compactMap { session -> SessionListItem? in
            let metadata = discoveredSessionMetadata[session.id] ?? DiscoveredSessionMetadata()
            guard !metadata.isHidden else { return nil }
            let fallbackTitle = session.name?.nonEmpty(or: session.sessionID) ?? session.sessionID
            let title = metadata.customName?.nonEmpty(or: fallbackTitle) ?? fallbackTitle

            return SessionListItem(
                id: "discovered-\(session.id)",
                source: .discovered(session.id),
                title: title,
                sessionID: session.sessionID,
                cwd: session.cwd,
                lastActivityAt: session.lastActivityAt,
                isPinned: metadata.isPinned,
                isLive: session.isLive,
                isClosed: !session.isLive,
                statusText: session.isLive ? "已打开" : nil
            )
        }
        .sorted(by: stableSessionListItemSort)
    }

    var allSessions: [ManagedSession] {
        sessions.sorted(by: stableSessionSort)
    }

    var launchButtonTitle: String {
        "启动"
    }

    var sessionNamePreview: [String] {
        guard let profile = selectedProfile else { return [] }
        return (1...resolvedLaunchCount).map { profile.resolvedSessionName(index: $0) }
    }

    func createProfile() {
        var profile = LaunchProfile.makeDefault()
        profile.name = uniqueProfileName(base: profile.name)
        profiles.insert(profile, at: 0)
        selectedProfileID = profile.id
        persistProfiles()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func duplicateSelectedProfile() {
        saveSelectedProfileAs(name: selectedProfile.map { "\($0.name) 副本" } ?? "新配置 副本")
    }

    func renameSelectedProfile(to name: String) {
        guard let selectedProfileID else { return }
        renameProfile(selectedProfileID, to: name)
    }

    func renameProfile(_ profileID: LaunchProfile.ID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let fallback = profiles[index].name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: fallback)
        profiles[index].name = uniqueProfileName(base: trimmedName, excluding: profileID)
        profiles[index].updatedAt = Date()
        persistProfiles()
        refreshPreview()
    }

    func saveSelectedProfileAs(name: String) {
        guard let selectedProfileID else { return }
        saveProfileAs(selectedProfileID, name: name)
    }

    func saveProfileAs(_ profileID: LaunchProfile.ID, name: String) {
        guard var profile = profiles.first(where: { $0.id == profileID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        profile.id = UUID()
        profile.name = uniqueProfileName(base: trimmedName.nonEmpty(or: "\(profile.name) 副本"))
        profile.createdAt = now
        profile.updatedAt = now
        profiles.insert(profile, at: 0)
        selectedProfileID = profile.id
        persistProfiles()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func saveSelectedProfileNow() {
        persistProfiles()
    }

    func deleteSelectedProfile() {
        guard let selectedProfileID else { return }
        deleteProfile(selectedProfileID)
    }

    func deleteProfile(_ profileID: LaunchProfile.ID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles.remove(at: index)
        if profiles.isEmpty {
            profiles = [LaunchProfile.makeDefault()]
        }
        if selectedProfileID == profileID {
            selectedProfileID = profiles.first?.id
        } else if selectedProfileID == nil {
            selectedProfileID = profiles.first?.id
        }
        persistProfiles()
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func moveProfile(_ draggedProfileID: LaunchProfile.ID, to targetProfileID: LaunchProfile.ID) {
        guard draggedProfileID != targetProfileID,
              let sourceIndex = profiles.firstIndex(where: { $0.id == draggedProfileID }),
              let targetIndex = profiles.firstIndex(where: { $0.id == targetProfileID }) else {
            return
        }

        let profile = profiles.remove(at: sourceIndex)
        let destinationIndex = sourceIndex < targetIndex ? max(targetIndex - 1, 0) : targetIndex
        profiles.insert(profile, at: destinationIndex)
        persistProfiles()
        refreshPreview()
    }

    func selectProfile(_ profileID: LaunchProfile.ID?) {
        selectedProfileID = profileID
        syncLaunchCountInputFromSelectedProfile()
        refreshPreview()
    }

    func selectSession(_ sessionID: ManagedSession.ID?) {
        selectedSessionID = sessionID
    }

    func selectDiscoveredSession(_ sessionID: String?) {
        selectedDiscoveredSessionID = sessionID
        transcriptLoadGeneration += 1
        let generation = transcriptLoadGeneration

        guard let sessionID else {
            allTranscriptMessages = []
            transcriptDisplayCount = 0
            selectedTranscriptMessages = []
            return
        }

        allTranscriptMessages = []
        transcriptDisplayCount = 0
        selectedTranscriptMessages = []

        sessionDiscoveryQueue.async { [claudeSessionDiscovery] in
            let messages = claudeSessionDiscovery.loadTranscriptMessages(sessionID: sessionID)
            DispatchQueue.main.async {
                guard generation == self.transcriptLoadGeneration,
                      self.selectedDiscoveredSessionID == sessionID else {
                    return
                }
                self.allTranscriptMessages = messages
                self.transcriptDisplayCount = min(self.transcriptPageSize, messages.count)
                self.applyTranscriptDisplayWindow()
            }
        }
    }

    func selectSessionListItem(_ item: SessionListItem) {
        selectedSessionID = nil
        switch item.source {
        case .managed:
            selectDiscoveredSession(nil)
        case .discovered(let sessionID):
            selectDiscoveredSession(sessionID)
        }
    }

    var hasMoreTranscriptHistory: Bool {
        transcriptDisplayCount < allTranscriptMessages.count
    }

    func loadMoreTranscriptHistoryIfNeeded(triggerMessageID: String) {
        guard hasMoreTranscriptHistory,
              triggerMessageID == selectedTranscriptMessages.first?.id else {
            return
        }
        transcriptDisplayCount = min(transcriptDisplayCount + transcriptPageSize, allTranscriptMessages.count)
        applyTranscriptDisplayWindow()
    }

    func isSessionListItemSelected(_ item: SessionListItem) -> Bool {
        switch item.source {
        case .managed:
            return false
        case .discovered(let sessionID):
            return selectedDiscoveredSessionID == sessionID
        }
    }

    func reloadDiscoveredSessions() {
        sessionDiscoveryGeneration += 1
        let generation = sessionDiscoveryGeneration
        isDiscoveringSessions = true
        let startedAt = Date()

        sessionDiscoveryQueue.async { [claudeSessionDiscovery] in
            let sessions = claudeSessionDiscovery.discoverAllSessions()
            DispatchQueue.main.async {
                guard generation == self.sessionDiscoveryGeneration else { return }

                self.discoveredSessions = sessions
                self.isDiscoveringSessions = false

                let visibleIDs = Set(self.sessionListItems.map(\.id))
                let selectedListID = self.selectedDiscoveredSessionID.flatMap(self.sessionListID(forSessionID:))
                let currentSelectionStillExists = selectedListID.map { visibleIDs.contains($0) } ?? false

                if !currentSelectionStillExists {
                    if let firstItem = self.sessionListItems.first {
                        self.selectSessionListItem(firstItem)
                    } else {
                        self.selectedDiscoveredSessionID = nil
                        self.allTranscriptMessages = []
                        self.transcriptDisplayCount = 0
                        self.selectedTranscriptMessages = []
                    }
                } else {
                    self.selectDiscoveredSession(self.selectedDiscoveredSessionID)
                }

                self.analyticsService.track(
                    name: "session_list_refreshed",
                    properties: [
                        "discovered_count": String(sessions.count),
                        "duration_ms": String(Int(Date().timeIntervalSince(startedAt) * 1000))
                    ]
                )
            }
        }
    }

    func setPinned(for item: SessionListItem, pinned: Bool) {
        switch item.source {
        case .managed(let sessionID):
            setSessionPinned(sessionID, pinned: pinned)
        case .discovered(let sessionID):
            var metadata = discoveredSessionMetadata[sessionID] ?? DiscoveredSessionMetadata()
            metadata.isPinned = pinned
            discoveredSessionMetadata[sessionID] = metadata
            analyticsService.track(
                name: "session_pin_toggled",
                properties: [
                    "session_id": sessionID,
                    "source": "discovered",
                    "pinned": pinned ? "true" : "false"
                ]
            )
            persistDiscoveredSessionMetadata()
            reloadDiscoveredSessions()
        }
    }

    func renameSessionListItem(_ item: SessionListItem, to name: String) {
        switch item.source {
        case .managed(let sessionID):
            updateSessionName(sessionID, name: name)
        case .discovered(let sessionID):
            renameDiscoveredSession(sessionID: sessionID, name: name)
        }
        reloadDiscoveredSessions()
    }

    func deleteSessionListItem(_ item: SessionListItem) {
        switch item.source {
        case .managed(let sessionID):
            terminateAndDeleteManagedSession(sessionID)
        case .discovered(let sessionID):
            terminateAndHideDiscoveredSession(sessionID: sessionID)
        }
        reloadDiscoveredSessions()
    }

    func reopenSessionListItem(_ item: SessionListItem) {
        switch item.source {
        case .managed(let sessionID):
            reopenSession(sessionID)
        case .discovered(let sessionID):
            reopenDiscoveredSession(sessionID: sessionID)
        }
        reloadDiscoveredSessions()
    }

    func canReopenSessionListItem(_ item: SessionListItem) -> Bool {
        item.isClosed
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

    func browseContextFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if panel.runModal() == .OK {
            let paths = panel.urls.map(\.path)
            updateSelectedProfile { profile in
                for path in paths where !profile.contextFilePaths.contains(path) {
                    profile.contextFilePaths.append(path)
                }
            }
        }
    }

    func removeContextFile(_ path: String) {
        updateSelectedProfile { profile in
            profile.contextFilePaths.removeAll { $0 == path }
        }
    }

    func launchSelectedProfile() {
        launch(profileID: selectedProfileID, count: resolvedLaunchCount)
    }

    func launch(profileID: LaunchProfile.ID?, count: Int?) {
        guard let profile = profileID.flatMap({ id in profiles.first(where: { $0.id == id }) }) ?? selectedProfile else { return }
        var launchProfile = profile
        launchProfile.batchCount = max(count ?? resolvedLaunchCount, 1)

        if let error = launchCoordinator.validate(profile: launchProfile) {
            errorMessage = error
            analyticsService.track(
                name: "session_launch_failed",
                properties: [
                    "profile_id": launchProfile.id.uuidString,
                    "batch_count": String(launchProfile.batchCount),
                    "error_message": error
                ],
                flushImmediately: true
            )
            return
        }

        errorMessage = nil
        let preparations = launchCoordinator.prepareLaunches(for: launchProfile)
        analyticsService.track(
            name: "session_launch_requested",
            properties: [
                "profile_id": launchProfile.id.uuidString,
                "batch_count": String(launchProfile.batchCount),
                "model": launchProfile.model,
                "permission_mode": launchProfile.permissionMode.rawValue,
                "launch_mode": launchProfile.launchMode.rawValue
            ]
        )
        for preparation in preparations {
            let automationPlan = startupAutomationCoordinator.makePlan(for: launchProfile, sessionName: preparation.sessionName)
            do {
                let launchResult = try launchCoordinator.launchInTerminal(preparation)
                let appliedFontSize = launchProfile.advancedSettingsEnabled ? try? launchCoordinator.applyTerminalAppearance(
                    windowID: launchResult.windowID,
                    tabIndex: launchResult.tabIndex,
                    preference: launchProfile.terminalFontPreference,
                    customFontSize: launchProfile.customTerminalFontSize
                ) : nil
                let session = ManagedSession.make(
                    origin: .appLaunched,
                    profile: launchProfile,
                    displayName: preparation.sessionName,
                    command: preparation.shellCommand,
                    status: .running,
                    terminalWindowID: launchResult.windowID,
                    terminalTabIndex: launchResult.tabIndex,
                    summary: automationPlan.summaryPlaceholder,
                    summaryStatus: .placeholder,
                    canSendCommands: true,
                    canTerminate: false,
                    renameCommandTemplate: "/rename {name}"
                )
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
                analyticsService.track(
                    name: "session_launch_succeeded",
                    properties: [
                        "session_id": session.id.uuidString,
                        "profile_id": launchProfile.id.uuidString,
                        "terminal_window_id": String(launchResult.windowID),
                        "terminal_tab_index": String(launchResult.tabIndex)
                    ],
                    flushImmediately: true
                )
            } catch {
                let session = ManagedSession.make(
                    origin: .appLaunched,
                    profile: launchProfile,
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
                analyticsService.track(
                    name: "session_launch_failed",
                    properties: [
                        "profile_id": launchProfile.id.uuidString,
                        "session_id": session.id.uuidString,
                        "error_message": error.localizedDescription
                    ],
                    flushImmediately: true
                )
            }
        }
        persistSessions()
    }

    func updateSelectedSessionName(_ name: String) {
        guard let selectedSessionID else { return }
        updateSessionName(selectedSessionID, name: name)
    }

    func updateSessionName(_ sessionID: ManagedSession.ID, name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let fallbackName = sessions[index].launchedName
        let newName = name.nonEmpty(or: fallbackName)

        sessions[index].displayName = newName

        let syncSucceeded = updateTerminalTitle(newName, for: sessions[index])
        analyticsService.track(
            name: "session_renamed",
            properties: [
                "session_id": sessions[index].id.uuidString,
                "source": "managed",
                "sync_to_terminal_success": syncSucceeded ? "true" : "false"
            ],
            flushImmediately: true
        )
        if syncSucceeded {
            sessions[index].claudeSessionName = newName
            sessions[index].errorMessage = nil
        } else {
            sessions[index].errorMessage = "改名未同步到终端标题。"
            errorMessage = sessions[index].errorMessage
        }

        touchManagedSession(at: index)
    }

    func setSessionPinned(_ sessionID: ManagedSession.ID, pinned: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isPinned = pinned
        analyticsService.track(
            name: "session_pin_toggled",
            properties: [
                "session_id": sessions[index].id.uuidString,
                "source": "managed",
                "pinned": pinned ? "true" : "false"
            ]
        )
        touchManagedSession(at: index)
    }

    func deleteSession(_ sessionID: ManagedSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let deletedSession = sessions[index]
        analyticsService.track(
            name: "session_deleted_or_hidden",
            properties: [
                "session_id": deletedSession.id.uuidString,
                "source": "managed"
            ],
            flushImmediately: true
        )
        sessions.remove(at: index)
        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first?.id
        }
        persistSessions()
    }

    func reopenSession(_ sessionID: ManagedSession.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        guard let profileID = session.profileID,
              profiles.contains(where: { $0.id == profileID }) else {
            errorMessage = "找不到原配置，无法重新打开。"
            return
        }
        analyticsService.track(
            name: "session_reopen",
            properties: [
                "session_id": session.id.uuidString,
                "source": "managed"
            ],
            flushImmediately: true
        )
        launch(profileID: profileID, count: 1)
    }

    func updateSelectedSessionNotes(_ notes: String) {
        guard let index = selectedSessionIndex else { return }
        sessions[index].notes = notes
        touchManagedSession(at: index)
    }

    func generateSummaryPlaceholder() {
        guard let index = selectedSessionIndex else { return }
        let managedSession = sessions[index]
        sessions[index].summary = "基于配置「\(managedSession.profileName)」启动，当前会话名为「\(managedSession.displayName)」，等待补充对话摘要。"
        sessions[index].summaryStatus = .placeholder
        touchManagedSession(at: index)
    }

    func archiveSelectedSession() {
        guard let index = selectedSessionIndex else { return }
        sessions[index].status = .archived
        touchManagedSession(at: index)
    }

    func terminateSelectedSession() {
        guard let index = selectedSessionIndex else { return }
        if terminateManagedSession(at: index) {
            touchManagedSession(at: index)
        }
    }

    func refreshPreview() {
        guard let profile = selectedProfile else {
            commandPreview = ""
            return
        }
        let previewProfile = profileWithResolvedBatchCount(profile)
        commandPreview = launchCoordinator.prepareLaunches(for: previewProfile).first?.shellCommand ?? ""
    }

    var resolvedLaunchCount: Int {
        if let count = Int(launchCountInput), count >= 1 {
            return count
        }
        return max(selectedProfile?.batchCount ?? 1, 1)
    }

    private func renameDiscoveredSession(sessionID: String, name: String) {
        guard let session = discoveredSessions.first(where: { $0.id == sessionID }) else { return }
        let fallbackTitle = session.name?.nonEmpty(or: session.sessionID) ?? session.sessionID
        let newName = name.nonEmpty(or: fallbackTitle)

        var syncSucceeded = false
        if let liveSession = claudeSessionDiscovery.discoverLiveSessions().first(where: { $0.sessionID == session.sessionID || $0.id == session.id }),
           let tty = liveSession.tty,
           let terminalTarget = launchCoordinator.findTerminalTarget(forTTY: tty) {
            do {
                try launchCoordinator.updateTerminalTitle(newName, windowID: terminalTarget.windowID, tabIndex: terminalTarget.tabIndex)
                syncSucceeded = true
            } catch {
                errorMessage = "改名同步失败：\(error.localizedDescription)"
            }
        }

        var metadata = discoveredSessionMetadata[sessionID] ?? DiscoveredSessionMetadata()
        metadata.customName = newName
        discoveredSessionMetadata[sessionID] = metadata
        persistDiscoveredSessionMetadata()

        analyticsService.track(
            name: "session_renamed",
            properties: [
                "session_id": sessionID,
                "source": "discovered",
                "sync_to_terminal_success": syncSucceeded ? "true" : "false"
            ],
            flushImmediately: true
        )

        if !syncSucceeded {
            errorMessage = "改名未同步到 Claude。"
        }
    }

    private func terminateAndDeleteManagedSession(_ sessionID: ManagedSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        _ = terminateManagedSession(at: index)
        deleteSession(sessionID)
    }

    private func terminateAndHideDiscoveredSession(sessionID: String) {
        if let liveSession = claudeSessionDiscovery.discoverLiveSessions().first(where: { $0.sessionID == sessionID || $0.id == sessionID }) {
            let terminated = launchCoordinator.terminateProcess(pid: liveSession.pid)
            if terminated {
                analyticsService.track(
                    name: "session_terminated",
                    properties: [
                        "session_id": sessionID,
                        "source": "discovered"
                    ],
                    flushImmediately: true
                )
            }
        }
        analyticsService.track(
            name: "session_deleted_or_hidden",
            properties: [
                "session_id": sessionID,
                "source": "discovered"
            ],
            flushImmediately: true
        )
        var metadata = discoveredSessionMetadata[sessionID] ?? DiscoveredSessionMetadata()
        metadata.isHidden = true
        discoveredSessionMetadata[sessionID] = metadata
        if selectedDiscoveredSessionID == sessionID {
            selectedDiscoveredSessionID = nil
            selectedTranscriptMessages = []
        }
        persistDiscoveredSessionMetadata()
    }

    private func reopenDiscoveredSession(sessionID: String) {
        guard let session = discoveredSessions.first(where: { $0.id == sessionID }) else { return }
        let fallbackTitle = session.name?.nonEmpty(or: session.sessionID) ?? session.sessionID
        let sessionName = discoveredSessionMetadata[sessionID]?.customName?.nonEmpty(or: fallbackTitle) ?? fallbackTitle
        analyticsService.track(
            name: "session_reopen",
            properties: [
                "session_id": sessionID,
                "source": "discovered"
            ],
            flushImmediately: true
        )
        do {
            _ = try launchCoordinator.resumeInTerminal(cwd: session.cwd, sessionID: session.sessionID, sessionName: sessionName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func terminateManagedSession(at index: Int) -> Bool {
        guard sessions.indices.contains(index) else { return false }
        guard sessions[index].canTerminate, let pid = sessions[index].pid else {
            errorMessage = "当前会话无法从应用内关闭。"
            return false
        }

        if launchCoordinator.terminateProcess(pid: pid) {
            sessions[index].status = .exited
            sessions[index].canTerminate = false
            analyticsService.track(
                name: "session_terminated",
                properties: [
                    "session_id": sessions[index].id.uuidString,
                    "source": "managed"
                ],
                flushImmediately: true
            )
            return true
        }

        errorMessage = "关闭会话失败。"
        return false
    }

    private func updateTerminalTitle(_ title: String, for session: ManagedSession) -> Bool {
        guard let windowID = session.terminalWindowID,
              let tabIndex = session.terminalTabIndex,
              session.status == .running || session.status == .launching else {
            return false
        }

        do {
            try launchCoordinator.updateTerminalTitle(title, windowID: windowID, tabIndex: tabIndex)
            return true
        } catch {
            errorMessage = "终端标题更新失败：\(error.localizedDescription)"
            return false
        }
    }


    private func persistDiscoveredSessionMetadata() {
        do {
            try sessionStore.saveDiscoveredSessionMetadata(discoveredSessionMetadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sessionListID(forSessionID sessionID: String) -> String? {
        if discoveredSessions.contains(where: { $0.id == sessionID }) {
            return "discovered-\(sessionID)"
        }
        return nil
    }

    private func stableSessionListItemSort(lhs: SessionListItem, rhs: SessionListItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        if lhs.isClosed != rhs.isClosed {
            return !lhs.isClosed && rhs.isClosed
        }
        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func profileWithResolvedBatchCount(_ profile: LaunchProfile) -> LaunchProfile {
        var copy = profile
        copy.batchCount = resolvedLaunchCount
        return copy
    }

    private func applyTranscriptDisplayWindow() {
        if transcriptDisplayCount == 0 {
            selectedTranscriptMessages = []
            return
        }
        selectedTranscriptMessages = Array(allTranscriptMessages.suffix(transcriptDisplayCount))
    }

    private func syncLaunchCountInputFromSelectedProfile() {
        launchCountInput = String(max(selectedProfile?.batchCount ?? 1, 1))
    }

    private func touchManagedSession(at index: Int) {
        let now = Date()
        sessions[index].updatedAt = now
        sessions[index].lastActivityAt = now
        persistSessions()
    }

    private func persistProfiles() {
        profileSaveStatus = .saving
        let snapshot = profiles
        profilePersistenceQueue.async { [profileStore] in
            do {
                try profileStore.saveProfiles(snapshot)
                DispatchQueue.main.async {
                    self.profileSaveStatus = .saved
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.profileSaveStatus = .failed(message)
                    self.errorMessage = message
                }
            }
        }
    }

    private func persistSessions() {
        sessions.sort(by: stableSessionSort)
        do {
            try sessionStore.saveSessions(sessions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stableSessionSort(lhs: ManagedSession, rhs: ManagedSession) -> Bool {
        let leftPinned = lhs.isPinned ?? false
        let rightPinned = rhs.isPinned ?? false
        if leftPinned != rightPinned {
            return leftPinned && !rightPinned
        }

        let rank: (ManagedSessionStatus) -> Int = {
            switch $0 {
            case .running: 0
            case .launching: 1
            case .failed: 2
            case .archived: 3
            case .exited: 4
            }
        }
        let leftRank = rank(lhs.status)
        let rightRank = rank(rhs.status)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if lhs.lastActivityAt != rhs.lastActivityAt {
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
        return lhs.createdAt > rhs.createdAt
    }

    private func uniqueProfileName(base: String, excluding profileID: LaunchProfile.ID? = nil) -> String {
        let normalizedBase = base.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty(or: "新配置")
        var candidate = normalizedBase
        var index = 2
        while profiles.contains(where: {
            $0.id != profileID && $0.name == candidate
        }) {
            candidate = "\(normalizedBase) \(index)"
            index += 1
        }
        return candidate
    }
}
