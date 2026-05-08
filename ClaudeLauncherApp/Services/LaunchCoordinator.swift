import AppKit
import Foundation

struct LaunchPreparation {
    let sessionName: String
    let shellCommand: String
    let pidFilePath: String?
}

struct TerminalLaunchResult {
    let windowID: Int
    let tabIndex: Int
}

struct TerminalTarget {
    let windowID: Int
    let tabIndex: Int
}

final class LaunchCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(profile: LaunchProfile) -> String? {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "配置名称不能为空。"
        }

        if !fileManager.fileExists(atPath: profile.workingDirectory) {
            return "工作目录不存在。"
        }

        for path in profile.contextFilePaths where !fileManager.fileExists(atPath: path) {
            return "上下文文件不存在：\(path)"
        }

        if profile.batchCount < 1 {
            return "批量启动数量至少为 1。"
        }

        return nil
    }

    func prepareLaunches(for profile: LaunchProfile) -> [LaunchPreparation] {
        (1...profile.batchCount).map { index in
            let sessionName = profile.resolvedSessionName(index: index)
            let pidFilePath = (profile.advancedSettingsEnabled && profile.startupRenameEnabled) ? startupPIDFilePath(for: profile.cliKind) : nil
            return LaunchPreparation(
                sessionName: sessionName,
                shellCommand: buildShellCommand(profile: profile, sessionName: sessionName, pidFilePath: pidFilePath),
                pidFilePath: pidFilePath
            )
        }
    }

    func resumeInTerminal(cliKind: CLIKind, cwd: String, sessionID: String, sessionName: String) throws -> TerminalLaunchResult {
        let command = buildResumeShellCommand(cliKind: cliKind, cwd: cwd, sessionID: sessionID)
        return try launch(LaunchPreparation(sessionName: sessionName, shellCommand: command, pidFilePath: nil), in: .terminal)
    }

    func launch(_ preparation: LaunchPreparation, in terminalApp: LaunchTerminalApp) throws -> TerminalLaunchResult {
        switch terminalApp {
        case .terminal:
            return try launchInTerminal(preparation)
        case .ghostty:
            return try launchInGhostty(preparation)
        }
    }

    func launchInGhosttyMergedIntoExistingWindow(_ preparations: [LaunchPreparation]) throws -> [TerminalLaunchResult] {
        guard let first = preparations.first else { return [] }
        let ghosttyCommand = "/bin/sh -lc \(first.shellCommand.shellEscaped)"
        let output = try runAppleScript(
            """
            tell application "Ghostty"
                activate
                set surfaceConfig to new surface configuration
                set command of surfaceConfig to "\(ghosttyCommand.appleScriptEscaped)"
                set wait after command of surfaceConfig to true
                if (count of windows) is 0 then
                    set targetWindow to new window with configuration surfaceConfig
                else
                    set targetWindow to front window
                    activate window targetWindow
                    set targetTerminal to focused terminal of selected tab of targetWindow
                    set createdTerminal to split targetTerminal direction right with configuration surfaceConfig
                    focus createdTerminal
                end if
                delay 0.2
                return (id of targetWindow as string)
            end tell
            """
        )
        let ghosttyWindowID = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ghosttyWindowID.isEmpty else {
            throw NSError(domain: "LaunchCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法并入 Ghostty 窗口。"])
        }

        var results: [TerminalLaunchResult] = [TerminalLaunchResult(windowID: 0, tabIndex: 0)]
        if preparations.count > 1 {
            for preparation in preparations.dropFirst() {
                results.append(try launchInGhostty(preparation, targetWindowID: ghosttyWindowID))
            }
        }
        return results
    }

    func launchInTerminal(_ preparation: LaunchPreparation) throws -> TerminalLaunchResult {
        let output = try runAppleScript(
            """
            tell application "Terminal"
                activate
                set newTab to do script "\(preparation.shellCommand.appleScriptEscaped)"
                delay 0.2
                set theWindow to front window
                set windowID to id of theWindow
                set tabIndex to 1
                repeat with i from 1 to count of tabs of theWindow
                    if item i of tabs of theWindow is newTab then
                        set tabIndex to i
                        exit repeat
                    end if
                end repeat
                return (windowID as string) & "," & (tabIndex as string)
            end tell
            """
        )

        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")
            .compactMap { Int($0) }

        guard parts.count == 2 else {
            throw NSError(domain: "LaunchCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取 Terminal 会话信息。"])
        }

        NSApp.activate(ignoringOtherApps: true)
        return TerminalLaunchResult(windowID: parts[0], tabIndex: parts[1])
    }

    func launchInGhostty(_ preparation: LaunchPreparation) throws -> TerminalLaunchResult {
        let output = try runAppleScript(
            """
            tell application "Ghostty"
                activate
                set surfaceConfig to new surface configuration
                set command of surfaceConfig to "/bin/sh -lc \(preparation.shellCommand.shellEscaped.appleScriptEscaped)"
                set wait after command of surfaceConfig to true
                set targetWindow to new window with configuration surfaceConfig
                delay 0.2
                return (id of targetWindow as string)
            end tell
            """
        )

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LaunchCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法创建 Ghostty 会话窗口。"])
        }

        return TerminalLaunchResult(windowID: 0, tabIndex: 0)
    }

    func launchInGhostty(_ preparation: LaunchPreparation, targetWindowID: String) throws -> TerminalLaunchResult {
        let ghosttyCommand = "/bin/sh -lc \(preparation.shellCommand.shellEscaped)"
        let output = try runAppleScript(
            """
            tell application "Ghostty"
                activate
                set targetWindow to first window whose id is "\(targetWindowID.appleScriptEscaped)"
                activate window targetWindow
                set targetTerminal to focused terminal of selected tab of targetWindow
                set surfaceConfig to new surface configuration
                set command of surfaceConfig to "\(ghosttyCommand.appleScriptEscaped)"
                set wait after command of surfaceConfig to true
                set createdTerminal to split targetTerminal direction right with configuration surfaceConfig
                focus createdTerminal
                delay 0.2
                return (id of targetWindow as string)
            end tell
            """
        )

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "LaunchCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法向 Ghostty 专属窗口追加会话。"])
        }

        return TerminalLaunchResult(windowID: 0, tabIndex: 0)
    }

    func applyTerminalAppearance(windowID: Int, tabIndex: Int, preference: TerminalFontPreference, customFontSize: String) throws -> Int? {
        let fontSize: Int?
        switch preference {
        case .large:
            fontSize = 16
        case .medium:
            fontSize = 14
        case .systemDefault:
            fontSize = 12
        case .custom:
            if let size = Int(customFontSize.trimmingCharacters(in: .whitespacesAndNewlines)), size >= 9, size <= 48 {
                fontSize = size
            } else {
                fontSize = nil
            }
        }

        guard let fontSize else { return nil }

        let output = try runAppleScript(
            """
            tell application "Terminal"
                set theWindow to first window whose id is \(windowID)
                set theTab to tab \(tabIndex) of theWindow
                set current settings of theTab to current settings of theTab
                set font size of current settings of theTab to \(fontSize)
                delay 0.05
                return font size of current settings of theTab as string
            end tell
            """
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return Int(output)
    }

    func sendCommand(_ command: String, toWindowID windowID: Int, tabIndex: Int) throws {
        _ = try runAppleScript(
            """
            tell application "Terminal"
                set theWindow to first window whose id is \(windowID)
                set selected tab of theWindow to tab \(tabIndex) of theWindow
                do script "\(command.appleScriptEscaped)" in tab \(tabIndex) of theWindow
            end tell
            """
        )
    }

    func updateTerminalTitle(_ title: String, windowID: Int, tabIndex: Int) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        _ = try runAppleScript(
            """
            tell application "Terminal"
                set theWindow to first window whose id is \(windowID)
                set custom title of tab \(tabIndex) of theWindow to "\(trimmedTitle.appleScriptEscaped)"
            end tell
            """
        )
    }

    func findTerminalTarget(forTTY tty: String) -> TerminalTarget? {
        let normalizedTTY = tty
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/dev/", with: "")
        guard !normalizedTTY.isEmpty else { return nil }
        let output = try? runAppleScript(
            """
            tell application "Terminal"
                repeat with theWindow in windows
                    repeat with i from 1 to count of tabs of theWindow
                        try
                            set tabTTY to tty of tab i of theWindow
                            if (tabTTY as string) is equal to "/dev/\(normalizedTTY.appleScriptEscaped)" then
                                return (id of theWindow as string) & "," & (i as string)
                            end if
                        end try
                    end repeat
                end repeat
                return ""
            end tell
            """
        )
        guard let output else { return nil }
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return TerminalTarget(windowID: parts[0], tabIndex: parts[1])
    }

    func terminalTTY(windowID: Int, tabIndex: Int) -> String? {
        let output = try? runAppleScript(
            """
            tell application "Terminal"
                set theWindow to first window whose id is \(windowID)
                set theTab to tab \(tabIndex) of theWindow
                try
                    return tty of theTab as string
                on error
                    return ""
                end try
            end tell
            """
        )
        let tty = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tty.isEmpty else { return nil }
        return tty
    }

    func terminateProcess(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", String(pid)]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func sendCommandToProcessTTY(command: String, pid: Int32) -> Bool {
        let ttyProcess = Process()
        let ttyPipe = Pipe()
        ttyProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
        ttyProcess.arguments = ["-o", "tty=", "-p", String(pid)]
        ttyProcess.standardOutput = ttyPipe

        do {
            try ttyProcess.run()
            ttyProcess.waitUntilExit()
            let tty = String(decoding: ttyPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tty.isEmpty, tty != "??" else { return false }

            let writeProcess = Process()
            writeProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            writeProcess.arguments = ["-c", "printf '%s\\n' \"\(command.shellCommandEscapedForDoubleQuotes)\" > /dev/\(tty)"]
            try writeProcess.run()
            writeProcess.waitUntilExit()
            return writeProcess.terminationStatus == 0
        } catch {
            return false
        }
    }

    func startupMarker(from pidFilePath: String) -> (pid: Int32, tty: String?)? {
        guard fileManager.fileExists(atPath: pidFilePath),
              let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8) else {
            return nil
        }
        let lines = content
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(first), pid > 0 else { return nil }
        let ttyLine = lines.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tty = ttyLine.isEmpty ? nil : ttyLine
        return (pid: pid, tty: tty)
    }

    private func buildShellCommand(profile: LaunchProfile, sessionName: String, pidFilePath: String?) -> String {
        switch profile.cliKind {
        case .claude:
            return buildClaudeShellCommand(profile: profile, sessionName: sessionName, pidFilePath: pidFilePath)
        case .gemini:
            return buildGeminiShellCommand(profile: profile, sessionName: sessionName, pidFilePath: pidFilePath)
        case .codex:
            return buildCodexShellCommand(profile: profile, sessionName: sessionName, pidFilePath: pidFilePath)
        }
    }

    private func buildResumeShellCommand(cliKind: CLIKind, cwd: String, sessionID: String) -> String {
        switch cliKind {
        case .claude:
            return "cd \(cwd.shellEscaped); claude --resume \(sessionID.shellEscaped)"
        case .gemini:
            return "cd \(cwd.shellEscaped); gemini --resume \(sessionID.shellEscaped)"
        case .codex:
            return "cd \(cwd.shellEscaped); codex resume \(sessionID.shellEscaped)"
        }
    }

    private func baseSegments(profile: LaunchProfile, pidFilePath: String?) -> [String] {
        var segments: [String] = []
        segments.append("cd \(profile.workingDirectory.shellEscaped)")

        if profile.advancedSettingsEnabled, let pidFilePath {
            let directory = (pidFilePath as NSString).deletingLastPathComponent
            segments.append("mkdir -p \(directory.shellEscaped)")
            segments.append("printf '%s\\n%s' \"$$\" \"$(tty | sed 's#^/dev/##')\" > \(pidFilePath.shellEscaped)")
        }

        return segments
    }

    private func buildClaudeShellCommand(profile: LaunchProfile, sessionName: String, pidFilePath: String?) -> String {
        var segments = baseSegments(profile: profile, pidFilePath: pidFilePath)
        var parts: [String] = ["exec claude"]

        if profile.startupRenameEnabled {
            parts.append("--name \(sessionName.shellEscaped)")
        }

        parts.append(claudePermissionArgument(for: profile.permissionMode))

        if let effort = supportedEffortArgument(for: profile) {
            parts.append("--effort \(effort.shellEscaped)")
        }

        if profile.launchMode == .bare {
            parts.append("--bare")
        }

        appendSharedLaunchArguments(to: &parts, profile: profile, additionalDirectoryFlag: "--add-dir")

        let startupPrompt = buildStartupPrompt(for: profile)
        if !startupPrompt.isEmpty {
            parts.append(startupPrompt.shellEscaped)
        }

        segments.append(parts.joined(separator: " "))
        return segments.joined(separator: "; ")
    }

    private func buildGeminiShellCommand(profile: LaunchProfile, sessionName: String, pidFilePath: String?) -> String {
        var segments = baseSegments(profile: profile, pidFilePath: pidFilePath)
        var parts: [String] = ["exec gemini", "--skip-trust"]

        if let approvalMode = geminiApprovalArgument(for: profile.permissionMode) {
            parts.append("--approval-mode \(approvalMode.shellEscaped)")
        }

        if profile.permissionMode == .auto || profile.permissionMode == .bypassPermissions {
            parts.append("--yolo")
        }

        appendSharedLaunchArguments(to: &parts, profile: profile, additionalDirectoryFlag: "--include-directories")

        if profile.startupRenameEnabled {
            let prompt = buildInteractivePrompt(for: profile, sessionName: sessionName)
            if !prompt.isEmpty {
                parts.append("--prompt-interactive \(prompt.shellEscaped)")
            }
        } else {
            let startupPrompt = buildStartupPrompt(for: profile)
            if !startupPrompt.isEmpty || !profile.startupMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let prompt = buildInteractivePrompt(for: profile, sessionName: sessionName)
                parts.append("--prompt-interactive \(prompt.shellEscaped)")
            }
        }

        segments.append(parts.joined(separator: " "))
        return segments.joined(separator: "; ")
    }

    private func buildCodexShellCommand(profile: LaunchProfile, sessionName: String, pidFilePath: String?) -> String {
        var segments = baseSegments(profile: profile, pidFilePath: pidFilePath)
        var parts: [String] = ["exec codex", "-C \(profile.workingDirectory.shellEscaped)"]

        if profile.permissionMode == .bypassPermissions {
            parts.append("--dangerously-bypass-approvals-and-sandbox")
        } else {
            if let approval = codexApprovalArgument(for: profile.permissionMode) {
                parts.append("--ask-for-approval \(approval.shellEscaped)")
            }
            parts.append(codexSandboxArgument(for: profile.permissionMode))
        }

        appendSharedLaunchArguments(to: &parts, profile: profile, additionalDirectoryFlag: "--add-dir")

        let prompt = buildInteractivePrompt(for: profile, sessionName: sessionName)
        if !prompt.isEmpty {
            parts.append(prompt.shellEscaped)
        }

        segments.append(parts.joined(separator: " "))
        return segments.joined(separator: "; ")
    }

    private func appendSharedLaunchArguments(to parts: inout [String], profile: LaunchProfile, additionalDirectoryFlag: String) {
        let trimmedModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            parts.append("--model \(trimmedModel.shellEscaped)")
        }

        let supportsSystemPrompt = profile.cliKind.capabilities.supportsAppendSystemPrompt
        let trimmedSystemPrompt = profile.appendSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if supportsSystemPrompt, !trimmedSystemPrompt.isEmpty {
            parts.append("--append-system-prompt \(trimmedSystemPrompt.shellEscaped)")
        }

        if profile.cliKind.capabilities.supportsAdditionalDirectories {
            for directory in profile.additionalDirectories.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
                parts.append("\(additionalDirectoryFlag) \(directory.shellEscaped)")
            }
        }
    }

    private func buildInteractivePrompt(for profile: LaunchProfile, sessionName: String) -> String {
        var blocks: [String] = []
        if profile.startupRenameEnabled, !profile.cliKind.capabilities.supportsNativeSessionRename {
            blocks.append("请将当前会话理解为：\(sessionName)")
        }
        let startupPrompt = buildStartupPrompt(for: profile)
        if !startupPrompt.isEmpty {
            blocks.append(startupPrompt)
        }
        let startupMessage = profile.startupMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !startupMessage.isEmpty {
            blocks.append(startupMessage)
        }
        return blocks.joined(separator: "\n\n")
    }

    private func buildStartupPrompt(for profile: LaunchProfile) -> String {
        var blocks: [String] = []

        if !profile.contextFilePaths.isEmpty {
            let fileList = profile.contextFilePaths.map { "@\($0)" }.joined(separator: "\n")
            blocks.append("请阅读以下文件：\n\(fileList)")
        }

        if profile.cliKind == .codex, !profile.contextFilePaths.isEmpty {
            blocks.append("如果当前 CLI 无法直接读取 @文件，请先根据这些路径在工作目录中打开对应文件。")
        }

        return blocks.joined(separator: "\n\n")
    }

    private func supportedEffortArgument(for profile: LaunchProfile) -> String? {
        guard profile.thinkingDepth != .auto else { return nil }
        return profile.thinkingDepth.rawValue
    }

    private func claudePermissionArgument(for mode: PermissionMode) -> String {
        switch mode {
        case .auto:
            return "--permission-mode 'auto'"
        case .bypassPermissions:
            return "--dangerously-skip-permissions"
        case .acceptEdits, .default, .dontAsk, .plan:
            return "--permission-mode \(mode.rawValue.shellEscaped)"
        case .untrusted, .never:
            return "--permission-mode default"
        }
    }

    private func geminiApprovalArgument(for mode: PermissionMode) -> String? {
        switch mode {
        case .default, .dontAsk, .untrusted, .never:
            return "default"
        case .acceptEdits:
            return "auto_edit"
        case .auto, .bypassPermissions:
            return "yolo"
        case .plan:
            return "plan"
        }
    }

    private func codexApprovalArgument(for mode: PermissionMode) -> String? {
        switch mode {
        case .default, .acceptEdits, .auto, .dontAsk:
            return "on-request"
        case .plan, .untrusted:
            return "untrusted"
        case .never:
            return "never"
        case .bypassPermissions:
            return nil
        }
    }

    private func codexSandboxArgument(for mode: PermissionMode) -> String {
        switch mode {
        case .bypassPermissions:
            return ""
        case .auto, .acceptEdits, .never:
            return "--sandbox workspace-write"
        case .default, .dontAsk, .plan, .untrusted:
            return "--sandbox read-only"
        }
    }

    private func startupPIDFilePath(for cliKind: CLIKind) -> String {
        let token = UUID().uuidString.lowercased()
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".\(cliKind.rawValue)-launcher", isDirectory: true)
        return directory.appendingPathComponent("\(token).pid").path
    }

    private func runAppleScript(_ source: String) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let errorOutput = String(decoding: errorData, as: UTF8.self)

        if process.terminationStatus != 0 {
            throw NSError(domain: "LaunchCoordinator", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorOutput.nonEmpty(or: "Terminal 操作失败。")])
        }

        return output
    }
}

private extension String {
    var shellEscaped: String {
        let escaped = replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    var shellCommandEscapedForDoubleQuotes: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
