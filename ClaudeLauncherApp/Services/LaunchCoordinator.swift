import AppKit
import Foundation

struct LaunchPreparation {
    let sessionName: String
    let shellCommand: String
}

struct TerminalLaunchResult {
    let windowID: Int
    let tabIndex: Int
}

struct MonitoredTerminalState {
    let exists: Bool
    let isBusy: Bool
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

        if profile.batchCount < 1 {
            return "批量启动数量至少为 1。"
        }

        return nil
    }

    func prepareLaunches(for profile: LaunchProfile, gateway: GatewayConfig?, apiKey: String?) -> [LaunchPreparation] {
        (1...profile.batchCount).map { index in
            let sessionName = profile.resolvedSessionName(index: index)
            return LaunchPreparation(
                sessionName: sessionName,
                shellCommand: buildShellCommand(profile: profile, gateway: gateway, apiKey: apiKey, sessionName: sessionName)
            )
        }
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

    func fetchTerminalState(windowID: Int, tabIndex: Int) throws -> MonitoredTerminalState {
        let output = try runAppleScript(
            """
            tell application "Terminal"
                if not (exists (first window whose id is \(windowID))) then
                    return "missing"
                end if
                set theWindow to first window whose id is \(windowID)
                if (count of tabs of theWindow) < \(tabIndex) then
                    return "missing"
                end if
                set isBusyValue to busy of tab \(tabIndex) of theWindow
                return "exists," & (isBusyValue as string)
            end tell
            """
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if output == "missing" {
            return MonitoredTerminalState(exists: false, isBusy: false)
        }

        let parts = output.split(separator: ",")
        if parts.count == 2 {
            return MonitoredTerminalState(exists: true, isBusy: String(parts[1]).lowercased() == "true")
        }

        return MonitoredTerminalState(exists: true, isBusy: false)
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

    private func buildShellCommand(profile: LaunchProfile, gateway: GatewayConfig?, apiKey: String?, sessionName: String) -> String {
        var segments: [String] = []
        segments.append("cd \(profile.workingDirectory.shellEscaped)")

        if let gateway {
            switch gateway.providerType {
            case .anthropic, .customGateway:
                if !gateway.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_BASE_URL=\(gateway.baseURL.shellEscaped)")
                }
                if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_API_KEY=\(apiKey.shellEscaped)")
                }
            case .bedrock:
                if !gateway.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_BEDROCK_BASE_URL=\(gateway.baseURL.shellEscaped)")
                }
                segments.append("export CLAUDE_CODE_SKIP_BEDROCK_AUTH='1'")
                if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_AUTH_TOKEN=\(apiKey.shellEscaped)")
                }
            case .vertex:
                if !gateway.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_VERTEX_BASE_URL=\(gateway.baseURL.shellEscaped)")
                }
                segments.append("export CLAUDE_CODE_SKIP_VERTEX_AUTH='1'")
                if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_AUTH_TOKEN=\(apiKey.shellEscaped)")
                }
            case .foundry:
                if !gateway.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_FOUNDRY_BASE_URL=\(gateway.baseURL.shellEscaped)")
                }
                segments.append("export CLAUDE_CODE_SKIP_FOUNDRY_AUTH='1'")
                if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append("export ANTHROPIC_AUTH_TOKEN=\(apiKey.shellEscaped)")
                }
            }
        }

        var claudeParts: [String] = []
        claudeParts.append("claude")
        claudeParts.append("-n \(sessionName.shellEscaped)")

        switch profile.permissionMode {
        case .auto:
            claudeParts.append("--permission-mode 'auto'")
        case .bypassPermissions:
            claudeParts.append("--dangerously-skip-permissions")
        default:
            claudeParts.append("--permission-mode \(profile.permissionMode.rawValue.shellEscaped)")
        }

        claudeParts.append("--effort \(profile.thinkingDepth.rawValue.shellEscaped)")

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

        let trimmedStartupMessage = profile.startupMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStartupMessage.isEmpty {
            claudeParts.append(trimmedStartupMessage.shellEscaped)
        }

        segments.append(claudeParts.joined(separator: " "))
        return segments.joined(separator: "; ")
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
