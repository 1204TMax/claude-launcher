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
            let pidFilePath = (profile.advancedSettingsEnabled && profile.startupRenameEnabled) ? startupPIDFilePath() : nil
            return LaunchPreparation(
                sessionName: sessionName,
                shellCommand: buildShellCommand(profile: profile, sessionName: sessionName, pidFilePath: pidFilePath),
                pidFilePath: pidFilePath
            )
        }
    }

    func resumeInTerminal(cwd: String, sessionID: String, sessionName: String) throws -> TerminalLaunchResult {
        let command = "cd \(cwd.shellEscaped); claude --resume \(sessionID.shellEscaped)"
        return try launchInTerminal(LaunchPreparation(sessionName: sessionName, shellCommand: command, pidFilePath: nil))
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

    private func buildShellCommand(profile: LaunchProfile, sessionName: String, pidFilePath: String?) -> String {
        var segments: [String] = []
        segments.append("cd \(profile.workingDirectory.shellEscaped)")

        if profile.advancedSettingsEnabled, let pidFilePath {
            let directory = (pidFilePath as NSString).deletingLastPathComponent
            segments.append("mkdir -p \(directory.shellEscaped)")
            segments.append("printf '%s\\n%s' \"$$\" \"$(tty | sed 's#^/dev/##')\" > \(pidFilePath.shellEscaped)")
        }

        var claudeParts: [String] = []
        claudeParts.append("exec claude")

        if profile.startupRenameEnabled {
            claudeParts.append("--name \(sessionName.shellEscaped)")
        }

        switch profile.permissionMode {
        case .auto:
            claudeParts.append("--permission-mode 'auto'")
        case .bypassPermissions:
            claudeParts.append("--dangerously-skip-permissions")
        default:
            claudeParts.append("--permission-mode \(profile.permissionMode.rawValue.shellEscaped)")
        }

        if let effort = supportedEffortArgument(for: profile) {
            claudeParts.append("--effort \(effort.shellEscaped)")
        }

        if profile.launchMode == .bare {
            claudeParts.append("--bare")
        }

        let trimmedModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            claudeParts.append("--model \(trimmedModel.shellEscaped)")
        }

        let trimmedSystemPrompt = profile.appendSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystemPrompt.isEmpty {
            claudeParts.append("--append-system-prompt \(trimmedSystemPrompt.shellEscaped)")
        }

        for directory in profile.additionalDirectories.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            claudeParts.append("--add-dir \(directory.shellEscaped)")
        }

        let startupPrompt = buildStartupPrompt(for: profile)
        if !startupPrompt.isEmpty {
            claudeParts.append(startupPrompt.shellEscaped)
        }

        segments.append(claudeParts.joined(separator: " "))
        return segments.joined(separator: "; ")
    }

    private func buildStartupPrompt(for profile: LaunchProfile) -> String {
        var blocks: [String] = []

        if !profile.contextFilePaths.isEmpty {
            let fileList = profile.contextFilePaths.map { "@\($0)" }.joined(separator: "\n")
            blocks.append("请阅读以下文件：\n\(fileList)")
        }

        return blocks.joined(separator: "\n\n")
    }

    private func supportedEffortArgument(for profile: LaunchProfile) -> String? {
        guard profile.thinkingDepth != .auto else { return nil }
        return profile.thinkingDepth.rawValue
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

    private func startupPIDFilePath() -> String {
        let token = UUID().uuidString.lowercased()
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/launcher", isDirectory: true)
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
