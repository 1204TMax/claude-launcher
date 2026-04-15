import XCTest
@testable import ClaudeLauncher

final class ClaudeLauncherTests: XCTestCase {
    func testResolvedSessionNameUsesTemplate() {
        var profile = LaunchProfile.makeDefault()
        profile.name = "Batch"
        profile.startupRenameTemplate = "{{profile}}-{{index}}"

        XCTAssertEqual(profile.resolvedSessionName(index: 3), "Batch-3")
    }

    func testLaunchCommandIncludesCoreSettingsWithoutAdvancedMode() {
        var profile = LaunchProfile.makeDefault()
        profile.advancedSettingsEnabled = false
        profile.model = "sonnet"
        profile.permissionMode = .acceptEdits
        profile.thinkingDepth = .high
        profile.launchMode = .bare
        profile.appendSystemPrompt = "额外系统提示"
        profile.additionalDirectories = ["/tmp"]
        profile.contextFilePaths = ["/tmp/context.md"]

        let command = LaunchCoordinator().prepareLaunches(for: profile).first?.shellCommand ?? ""

        XCTAssertTrue(command.contains("cd "))
        XCTAssertTrue(command.contains("exec claude"))
        XCTAssertTrue(command.contains("--model 'sonnet'"))
        XCTAssertTrue(command.contains("--permission-mode 'acceptEdits'"))
        XCTAssertTrue(command.contains("--effort 'high'"))
        XCTAssertTrue(command.contains("--bare"))
        XCTAssertTrue(command.contains("--append-system-prompt '额外系统提示'"))
        XCTAssertTrue(command.contains("--add-dir '/tmp'"))
        XCTAssertTrue(command.contains("@/tmp/context.md"))
    }

    func testMaxEffortFallsBackToHighForNonOpusModel() {
        var profile = LaunchProfile.makeDefault()
        profile.model = "sonnet"
        profile.thinkingDepth = .max

        let command = LaunchCoordinator().prepareLaunches(for: profile).first?.shellCommand ?? ""

        XCTAssertTrue(command.contains("--effort 'high'"))
        XCTAssertFalse(command.contains("--effort 'max'"))
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
        XCTAssertEqual(session.pid, 123)
        XCTAssertEqual(session.claudeSessionID, "session-1")
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
        XCTAssertEqual(ManagedSessionStatus.exited.displayName, "已结束")
        XCTAssertEqual(ManagedSessionStatus.archived.displayName, "已归档")
    }

    func testPermissionModeDisplayNames() {
        XCTAssertEqual(PermissionMode.acceptEdits.displayName, "允许编辑")
        XCTAssertEqual(PermissionMode.bypassPermissions.displayName, "最大权限")
    }

    func testSuggestedModelsContainCurrentAliases() {
        XCTAssertTrue(LaunchProfile.suggestedModels.contains("sonnet[1m]"))
        XCTAssertTrue(LaunchProfile.suggestedModels.contains("opus[1m]"))
        XCTAssertTrue(LaunchProfile.suggestedModels.contains("haiku"))
    }

    func testSessionOriginDisplayNames() {
        XCTAssertEqual(SessionOrigin.appLaunched.displayName, "本应用启动")
    }
}
