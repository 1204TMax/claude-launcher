import XCTest
@testable import ClaudeLauncher

final class ClaudeLauncherTests: XCTestCase {
    func testResolvedSessionNameUsesTemplate() {
        var profile = LaunchProfile.makeDefault()
        profile.name = "Batch"
        profile.startupRenameTemplate = "{{profile}}-{{index}}"

        XCTAssertEqual(profile.resolvedSessionName(index: 3), "Batch-3")
    }

    func testManagedSessionFactoryCopiesProfileSettings() {
        var profile = LaunchProfile.makeDefault()
        profile.name = "写代码"
        profile.model = "sonnet"
        profile.permissionMode = .dontAsk
        profile.launchMode = .bare
        profile.thinkingDepth = .high

        let session = ManagedSession.make(
            origin: .appLaunched,
            profile: profile,
            gatewayName: "默认 Anthropic",
            displayName: "写代码 1",
            command: "cd '/tmp'; claude -n '写代码 1'",
            status: .running,
            claudeSessionID: "session-1",
            pid: 123,
            terminalWindowID: 100,
            terminalTabIndex: 2,
            canSendCommands: true,
            canTerminate: true
        )

        XCTAssertEqual(session.origin, .appLaunched)
        XCTAssertEqual(session.profileName, "写代码")
        XCTAssertEqual(session.displayName, "写代码 1")
        XCTAssertEqual(session.model, "sonnet")
        XCTAssertEqual(session.permissionMode, .dontAsk)
        XCTAssertEqual(session.launchMode, .bare)
        XCTAssertEqual(session.thinkingDepth, .high)
        XCTAssertEqual(session.terminalWindowID, 100)
        XCTAssertEqual(session.terminalTabIndex, 2)
        XCTAssertEqual(session.claudeSessionName, "写代码 1")
        XCTAssertEqual(session.gatewayName, "默认 Anthropic")
        XCTAssertEqual(session.pid, 123)
        XCTAssertEqual(session.claudeSessionID, "session-1")
    }

    func testDiscoveredSessionFactoryUsesExternalOrigin() {
        let session = ManagedSession.make(
            origin: .discoveredExternal,
            profile: nil,
            gatewayName: nil,
            displayName: "外部会话",
            command: "claude (外部发现)",
            status: .running,
            claudeSessionID: "external-session",
            pid: 999,
            canSendCommands: false,
            canTerminate: true
        )

        XCTAssertEqual(session.origin, .discoveredExternal)
        XCTAssertEqual(session.profileName, "外部会话")
        XCTAssertFalse(session.canSendCommands)
        XCTAssertTrue(session.canTerminate)
    }

    func testDiscoveredClaudeSessionNormalizesBlankName() {
        let discovered = DiscoveredClaudeSession(
            id: "pid-1",
            pid: 1,
            sessionID: "s1",
            cwd: "/tmp",
            startedAt: nil,
            name: "   "
        )

        XCTAssertNil(discovered.normalizedName)
    }

    func testSummaryPlaceholderIncludesProfileAndSessionName() {
        let coordinator = StartupAutomationCoordinator()
        var profile = LaunchProfile.makeDefault()
        profile.name = "PRD整理"

        let plan = coordinator.makePlan(for: profile, sessionName: "PRD整理 2")

        XCTAssertTrue(plan.summaryPlaceholder.contains("PRD整理"))
        XCTAssertTrue(plan.summaryPlaceholder.contains("PRD整理 2"))
    }

    func testManagedSessionStatusDisplayNames() {
        XCTAssertEqual(ManagedSessionStatus.running.displayName, "运行中")
        XCTAssertEqual(ManagedSessionStatus.idle.displayName, "空闲")
        XCTAssertEqual(ManagedSessionStatus.exited.displayName, "已结束")
    }

    func testPermissionModeDisplayNames() {
        XCTAssertEqual(PermissionMode.acceptEdits.displayName, "自动接受编辑")
        XCTAssertEqual(PermissionMode.bypassPermissions.displayName, "跳过权限（危险）")
    }

    func testSuggestedModelsContainOfficialAliases() {
        XCTAssertTrue(LaunchProfile.suggestedModels.contains("sonnet"))
        XCTAssertTrue(LaunchProfile.suggestedModels.contains("opus"))
        XCTAssertTrue(LaunchProfile.suggestedModels.contains("sonnet[1m]"))
    }

    func testGatewayDefaultConfig() {
        let gateway = GatewayConfig.makeDefault()
        XCTAssertEqual(gateway.providerType, .anthropic)
        XCTAssertEqual(gateway.name, "默认 Anthropic")
        XCTAssertNotNil(UUID(uuidString: gateway.apiKeyReference))
    }

    func testSessionOriginDisplayNames() {
        XCTAssertEqual(SessionOrigin.appLaunched.displayName, "本应用启动")
        XCTAssertEqual(SessionOrigin.discoveredExternal.displayName, "外部发现")
    }
}
