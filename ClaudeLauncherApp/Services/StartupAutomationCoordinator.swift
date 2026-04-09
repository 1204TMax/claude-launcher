import Foundation

struct StartupAutomationPlan {
    let renameCommand: String?
    let startupMessage: String?
    let summaryPlaceholder: String
}

final class StartupAutomationCoordinator {
    func makePlan(for profile: LaunchProfile, sessionName: String) -> StartupAutomationPlan {
        let renameCommand: String?
        if profile.startupRenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            renameCommand = nil
        } else {
            renameCommand = "/rename \(sessionName)"
        }

        let startupMessage = profile.startupMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : profile.startupMessage

        let summaryPlaceholder = "基于配置「\(profile.name)」启动，当前会话名为「\(sessionName)」，等待补充对话摘要。"

        return StartupAutomationPlan(
            renameCommand: renameCommand,
            startupMessage: startupMessage,
            summaryPlaceholder: summaryPlaceholder
        )
    }
}
