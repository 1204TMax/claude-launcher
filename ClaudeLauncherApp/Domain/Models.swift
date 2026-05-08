import Foundation

enum CLIKind: String, Codable, CaseIterable, Identifiable {
    case claude
    case gemini
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .codex: "Codex"
        }
    }

    var executableName: String {
        switch self {
        case .claude: "claude"
        case .gemini: "gemini"
        case .codex: "codex"
        }
    }

    var capabilities: CLICapabilities {
        switch self {
        case .claude:
            return CLICapabilities(
                modelOptions: [
                    LaunchModelOption(id: "haiku", title: "Haiku 4.5", subtitle: "轻量高速"),
                    LaunchModelOption(id: "sonnet[1m]", title: "Sonnet 4.6", subtitle: "日常主力"),
                    LaunchModelOption(id: "opus[1m]", title: "Opus 4.7", subtitle: "复杂任务")
                ],
                permissionOptions: [.default, .acceptEdits, .plan, .auto, .bypassPermissions],
                thinkingDepthOptions: [.auto, .low, .medium, .high, .xhigh, .max],
                supportsLaunchMode: true,
                supportsAdditionalDirectories: true,
                supportsAppendSystemPrompt: true,
                supportsNativeSessionRename: true,
                transcriptAvailabilityNote: nil
            )
        case .gemini:
            return CLICapabilities(
                modelOptions: [
                    LaunchModelOption(id: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro Preview", subtitle: "当前主力"),
                    LaunchModelOption(id: "gemini-3-flash-preview", title: "Gemini 3 Flash Preview", subtitle: "日常主力"),
                    LaunchModelOption(id: "gemini-3.1-flash-lite-preview", title: "Gemini 3.1 Flash Lite Preview", subtitle: "轻量高速")
                ],
                permissionOptions: [.default, .acceptEdits, .plan, .auto],
                thinkingDepthOptions: [.auto],
                supportsLaunchMode: false,
                supportsAdditionalDirectories: true,
                supportsAppendSystemPrompt: false,
                supportsNativeSessionRename: false,
                transcriptAvailabilityNote: nil
            )
        case .codex:
            return CLICapabilities(
                modelOptions: [
                    LaunchModelOption(id: "gpt-5.5", title: "gpt-5.5", subtitle: "current"),
                    LaunchModelOption(id: "gpt-5.4", title: "gpt-5.4", subtitle: "everyday coding"),
                    LaunchModelOption(id: "gpt-5.4-mini", title: "gpt-5.4-mini", subtitle: "small and fast"),
                    LaunchModelOption(id: "gpt-5.3-codex", title: "gpt-5.3-codex", subtitle: "coding optimized"),
                    LaunchModelOption(id: "gpt-5.2", title: "gpt-5.2", subtitle: "long-running agents")
                ],
                permissionOptions: [.default, .untrusted, .never, .bypassPermissions],
                thinkingDepthOptions: [.auto],
                supportsLaunchMode: false,
                supportsAdditionalDirectories: true,
                supportsAppendSystemPrompt: false,
                supportsNativeSessionRename: false,
                transcriptAvailabilityNote: "当前仅支持读取 Codex 的用户输入历史。"
            )
        }
    }

    var defaultModel: String {
        capabilities.modelOptions.first?.id ?? ""
    }
}

struct CLICapabilities: Equatable {
    let modelOptions: [LaunchModelOption]
    let permissionOptions: [PermissionMode]
    let thinkingDepthOptions: [ThinkingDepth]
    let supportsLaunchMode: Bool
    let supportsAdditionalDirectories: Bool
    let supportsAppendSystemPrompt: Bool
    let supportsNativeSessionRename: Bool
    let transcriptAvailabilityNote: String?
}

enum LaunchTerminalApp: String, Codable, CaseIterable, Identifiable {
    case terminal
    case ghostty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .ghostty: "Ghostty"
        }
    }
}

enum GhosttyLaunchBehavior: String, Codable, CaseIterable, Identifiable {
    case mergeIntoExistingWindow
    case newWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mergeIntoExistingWindow: "并入已有窗口"
        case .newWindow: "新窗口打开"
        }
    }
}

enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case `default`
    case auto
    case acceptEdits
    case dontAsk
    case bypassPermissions
    case plan
    case untrusted
    case never

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "按需询问"
        case .acceptEdits: "允许编辑"
        case .plan: "只读模式"
        case .auto: "全自动"
        case .bypassPermissions: "最大权限"
        case .dontAsk: "白名单模式"
        case .untrusted: "仅信任命令"
        case .never: "从不询问"
        }
    }

    var helpText: String {
        switch self {
        case .default:
            return "在关键操作前询问确认。"
        case .acceptEdits:
            return "自动接受文件编辑，其余操作仍询问。"
        case .plan:
            return "只做分析与规划，不执行写入。"
        case .auto:
            return "自动批准支持范围内的操作。"
        case .bypassPermissions:
            return "跳过审批与沙箱保护，仅适合受控环境。"
        case .dontAsk:
            return "仅运行允许列表中的工具。"
        case .untrusted:
            return "仅信任只读或安全命令。"
        case .never:
            return "执行命令时不再请求人工确认。"
        }
    }
}

enum LaunchMode: String, Codable, CaseIterable, Identifiable {
    case standard
    case bare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "标准"
        case .bare: "精简"
        }
    }
}

enum ThinkingDepth: String, Codable, CaseIterable, Identifiable {
    case auto
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "自动"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .xhigh: "超高"
        case .max: "最大"
        }
    }
}

enum TerminalFontPreference: String, Codable, CaseIterable, Identifiable {
    case large
    case medium
    case systemDefault
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .large: "大"
        case .medium: "中"
        case .systemDefault: "默认"
        case .custom: "自定义"
        }
    }

    var note: String {
        switch self {
        case .large: "适合大屏"
        case .medium: "适合笔记本屏幕"
        case .systemDefault: ""
        case .custom: ""
        }
    }
}

enum ThemePreference: String, Codable, CaseIterable, Identifiable {
    case systemDefault
    case light
    case dark
    case darkDaltonized
    case lightDaltonized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemDefault: "默认"
        case .light: "浅色"
        case .dark: "深色"
        case .darkDaltonized: "深色无障碍"
        case .lightDaltonized: "浅色无障碍"
        }
    }
}

enum ProfileSaveStatus: Equatable {
    case idle
    case saving
    case saved
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "自动保存已开启"
        case .saving:
            return "保存中…"
        case .saved:
            return "已保存"
        case .failed:
            return "保存失败"
        }
    }
}

enum ManagedSessionStatus: String, Codable, CaseIterable, Identifiable {
    case launching
    case running
    case exited
    case failed
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .launching: "启动中"
        case .running: "运行中"
        case .exited: "已结束"
        case .failed: "启动失败"
        case .archived: "已归档"
        }
    }
}

enum SummaryStatus: String, Codable, CaseIterable, Identifiable {
    case none
    case placeholder
    case ready

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "未生成"
        case .placeholder: "占位摘要"
        case .ready: "已生成"
        }
    }
}

enum SessionOrigin: String, Codable, CaseIterable, Identifiable {
    case appLaunched

    var id: String { rawValue }

    var displayName: String { "本应用启动" }
}

enum AppSection: String, CaseIterable, Identifiable {
    case launch
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .launch: "启动"
        case .sessions: "会话历史"
        }
    }
}

enum TranscriptRole: String, Equatable {
    case user
    case assistant
    case system
}

struct TranscriptMessage: Identifiable, Equatable {
    let id: String
    let role: TranscriptRole
    let text: String
    let timestamp: Date?
}

struct DiscoveredSession: Identifiable, Equatable {
    let id: String
    let cliKind: CLIKind
    let sessionID: String
    let name: String?
    let cwd: String
    let startedAt: Date?
    let lastActivityAt: Date
    let preview: String
    let isLive: Bool
    let pid: Int32?
    let tty: String?
    let transcriptAvailabilityNote: String?

    var normalizedName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DiscoveredSessionMetadata: Codable, Equatable {
    var customName: String?
    var isPinned: Bool
    var isHidden: Bool

    init(customName: String? = nil, isPinned: Bool = false, isHidden: Bool = false) {
        self.customName = customName
        self.isPinned = isPinned
        self.isHidden = isHidden
    }
}

struct LaunchModelOption: Identifiable, Hashable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

struct LaunchProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var cliKind: CLIKind
    var name: String
    var workingDirectory: String
    var additionalDirectories: [String]
    var contextFilePaths: [String]
    var batchCount: Int
    var launchTerminalApp: LaunchTerminalApp
    var ghosttyLaunchBehavior: GhosttyLaunchBehavior
    var permissionMode: PermissionMode
    var launchMode: LaunchMode
    var thinkingDepth: ThinkingDepth
    var model: String
    var startupRenameEnabled: Bool
    var startupRenameTemplate: String
    var startupMessage: String
    var appendSystemPrompt: String
    var advancedSettingsEnabled: Bool
    var terminalFontPreference: TerminalFontPreference
    var customTerminalFontSize: String
    var themePreference: ThemePreference
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cliKind
        case name
        case workingDirectory
        case additionalDirectories
        case contextFilePaths
        case batchCount
        case launchTerminalApp
        case ghosttyLaunchBehavior
        case permissionMode
        case launchMode
        case thinkingDepth
        case model
        case startupRenameEnabled
        case startupRenameTemplate
        case startupMessage
        case appendSystemPrompt
        case advancedSettingsEnabled
        case terminalFontPreference
        case customTerminalFontSize
        case themePreference
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        cliKind: CLIKind,
        name: String,
        workingDirectory: String,
        additionalDirectories: [String],
        contextFilePaths: [String],
        batchCount: Int,
        launchTerminalApp: LaunchTerminalApp,
        ghosttyLaunchBehavior: GhosttyLaunchBehavior,
        permissionMode: PermissionMode,
        launchMode: LaunchMode,
        thinkingDepth: ThinkingDepth,
        model: String,
        startupRenameEnabled: Bool,
        startupRenameTemplate: String,
        startupMessage: String,
        appendSystemPrompt: String,
        advancedSettingsEnabled: Bool,
        terminalFontPreference: TerminalFontPreference,
        customTerminalFontSize: String,
        themePreference: ThemePreference,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.cliKind = cliKind
        self.name = name
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.contextFilePaths = contextFilePaths
        self.batchCount = batchCount
        self.launchTerminalApp = launchTerminalApp
        self.ghosttyLaunchBehavior = ghosttyLaunchBehavior
        self.permissionMode = permissionMode
        self.launchMode = launchMode
        self.thinkingDepth = thinkingDepth
        self.model = model
        self.startupRenameEnabled = startupRenameEnabled
        self.startupRenameTemplate = startupRenameTemplate
        self.startupMessage = startupMessage
        self.appendSystemPrompt = appendSystemPrompt
        self.advancedSettingsEnabled = advancedSettingsEnabled
        self.terminalFontPreference = terminalFontPreference
        self.customTerminalFontSize = customTerminalFontSize
        self.themePreference = themePreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cliKind = try container.decodeIfPresent(CLIKind.self, forKey: .cliKind) ?? .claude
        name = try container.decode(String.self, forKey: .name)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        additionalDirectories = try container.decodeIfPresent([String].self, forKey: .additionalDirectories) ?? []
        contextFilePaths = try container.decodeIfPresent([String].self, forKey: .contextFilePaths) ?? []
        batchCount = try container.decodeIfPresent(Int.self, forKey: .batchCount) ?? 1
        launchTerminalApp = try container.decodeIfPresent(LaunchTerminalApp.self, forKey: .launchTerminalApp) ?? .terminal
        ghosttyLaunchBehavior = try container.decodeIfPresent(GhosttyLaunchBehavior.self, forKey: .ghosttyLaunchBehavior) ?? .mergeIntoExistingWindow
        permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode) ?? .default
        launchMode = try container.decodeIfPresent(LaunchMode.self, forKey: .launchMode) ?? .standard
        thinkingDepth = try container.decodeIfPresent(ThinkingDepth.self, forKey: .thinkingDepth) ?? .auto
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? cliKind.defaultModel
        startupRenameEnabled = try container.decodeIfPresent(Bool.self, forKey: .startupRenameEnabled) ?? false
        startupRenameTemplate = try container.decodeIfPresent(String.self, forKey: .startupRenameTemplate) ?? ""
        startupMessage = try container.decodeIfPresent(String.self, forKey: .startupMessage) ?? ""
        appendSystemPrompt = try container.decodeIfPresent(String.self, forKey: .appendSystemPrompt) ?? ""
        advancedSettingsEnabled = try container.decodeIfPresent(Bool.self, forKey: .advancedSettingsEnabled) ?? false
        terminalFontPreference = try container.decodeIfPresent(TerminalFontPreference.self, forKey: .terminalFontPreference) ?? .systemDefault
        customTerminalFontSize = try container.decodeIfPresent(String.self, forKey: .customTerminalFontSize) ?? ""
        themePreference = try container.decodeIfPresent(ThemePreference.self, forKey: .themePreference) ?? .systemDefault
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    static func modelOptions(for cliKind: CLIKind) -> [LaunchModelOption] {
        cliKind.capabilities.modelOptions
    }

    static func suggestedModels(for cliKind: CLIKind) -> [String] {
        modelOptions(for: cliKind).map(\.id)
    }

    static func makeDefault() -> LaunchProfile {
        LaunchProfile(
            id: UUID(),
            cliKind: .claude,
            name: "新配置",
            workingDirectory: NSHomeDirectory(),
            additionalDirectories: [],
            contextFilePaths: [],
            batchCount: 1,
            launchTerminalApp: .terminal,
            ghosttyLaunchBehavior: .mergeIntoExistingWindow,
            permissionMode: .default,
            launchMode: .standard,
            thinkingDepth: .auto,
            model: CLIKind.claude.defaultModel,
            startupRenameEnabled: false,
            startupRenameTemplate: "",
            startupMessage: "",
            appendSystemPrompt: "",
            advancedSettingsEnabled: false,
            terminalFontPreference: .systemDefault,
            customTerminalFontSize: "",
            themePreference: .systemDefault,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func resolvedSessionName(index: Int) -> String {
        startupRenameTemplate
            .replacingOccurrences(of: "{{profile}}", with: name)
            .replacingOccurrences(of: "{{index}}", with: String(index))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty(or: "\(name) \(index)")
    }
}

struct ManagedSession: Identifiable, Codable, Equatable {
    var id: UUID
    var cliKind: CLIKind
    var origin: SessionOrigin
    var profileID: UUID?
    var profileName: String
    var displayName: String
    var launchedName: String
    var sessionName: String?
    var sessionID: String?
    var pid: Int32?
    var notes: String
    var summary: String
    var summaryStatus: SummaryStatus
    var workingDirectory: String
    var model: String
    var permissionMode: PermissionMode
    var launchMode: LaunchMode
    var thinkingDepth: ThinkingDepth
    var command: String
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date
    var status: ManagedSessionStatus
    var isPinned: Bool?
    var errorMessage: String?
    var terminalWindowID: Int?
    var terminalTabIndex: Int?
    var canSendCommands: Bool
    var canTerminate: Bool
    var renameCommandTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case cliKind
        case origin
        case profileID
        case profileName
        case displayName
        case launchedName
        case sessionName
        case sessionID
        case claudeSessionName
        case claudeSessionID
        case pid
        case notes
        case summary
        case summaryStatus
        case workingDirectory
        case model
        case permissionMode
        case launchMode
        case thinkingDepth
        case command
        case createdAt
        case updatedAt
        case lastActivityAt
        case status
        case isPinned
        case errorMessage
        case terminalWindowID
        case terminalTabIndex
        case canSendCommands
        case canTerminate
        case renameCommandTemplate
    }

    init(
        id: UUID,
        cliKind: CLIKind,
        origin: SessionOrigin,
        profileID: UUID?,
        profileName: String,
        displayName: String,
        launchedName: String,
        sessionName: String?,
        sessionID: String?,
        pid: Int32?,
        notes: String,
        summary: String,
        summaryStatus: SummaryStatus,
        workingDirectory: String,
        model: String,
        permissionMode: PermissionMode,
        launchMode: LaunchMode,
        thinkingDepth: ThinkingDepth,
        command: String,
        createdAt: Date,
        updatedAt: Date,
        lastActivityAt: Date,
        status: ManagedSessionStatus,
        isPinned: Bool?,
        errorMessage: String?,
        terminalWindowID: Int?,
        terminalTabIndex: Int?,
        canSendCommands: Bool,
        canTerminate: Bool,
        renameCommandTemplate: String?
    ) {
        self.id = id
        self.cliKind = cliKind
        self.origin = origin
        self.profileID = profileID
        self.profileName = profileName
        self.displayName = displayName
        self.launchedName = launchedName
        self.sessionName = sessionName
        self.sessionID = sessionID
        self.pid = pid
        self.notes = notes
        self.summary = summary
        self.summaryStatus = summaryStatus
        self.workingDirectory = workingDirectory
        self.model = model
        self.permissionMode = permissionMode
        self.launchMode = launchMode
        self.thinkingDepth = thinkingDepth
        self.command = command
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.status = status
        self.isPinned = isPinned
        self.errorMessage = errorMessage
        self.terminalWindowID = terminalWindowID
        self.terminalTabIndex = terminalTabIndex
        self.canSendCommands = canSendCommands
        self.canTerminate = canTerminate
        self.renameCommandTemplate = renameCommandTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cliKind = try container.decodeIfPresent(CLIKind.self, forKey: .cliKind) ?? .claude
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .appLaunched
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName) ?? "会话"
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "会话"
        launchedName = try container.decodeIfPresent(String.self, forKey: .launchedName) ?? displayName
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName) ?? container.decodeIfPresent(String.self, forKey: .claudeSessionName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? container.decodeIfPresent(String.self, forKey: .claudeSessionID)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        summaryStatus = try container.decodeIfPresent(SummaryStatus.self, forKey: .summaryStatus) ?? .none
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? NSHomeDirectory()
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? cliKind.defaultModel
        permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode) ?? .default
        launchMode = try container.decodeIfPresent(LaunchMode.self, forKey: .launchMode) ?? .standard
        thinkingDepth = try container.decodeIfPresent(ThinkingDepth.self, forKey: .thinkingDepth) ?? .auto
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt) ?? updatedAt
        status = try container.decodeIfPresent(ManagedSessionStatus.self, forKey: .status) ?? .running
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        terminalWindowID = try container.decodeIfPresent(Int.self, forKey: .terminalWindowID)
        terminalTabIndex = try container.decodeIfPresent(Int.self, forKey: .terminalTabIndex)
        canSendCommands = try container.decodeIfPresent(Bool.self, forKey: .canSendCommands) ?? false
        canTerminate = try container.decodeIfPresent(Bool.self, forKey: .canTerminate) ?? false
        renameCommandTemplate = try container.decodeIfPresent(String.self, forKey: .renameCommandTemplate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cliKind, forKey: .cliKind)
        try container.encode(origin, forKey: .origin)
        try container.encodeIfPresent(profileID, forKey: .profileID)
        try container.encode(profileName, forKey: .profileName)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(launchedName, forKey: .launchedName)
        try container.encodeIfPresent(sessionName, forKey: .sessionName)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(pid, forKey: .pid)
        try container.encode(notes, forKey: .notes)
        try container.encode(summary, forKey: .summary)
        try container.encode(summaryStatus, forKey: .summaryStatus)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encode(model, forKey: .model)
        try container.encode(permissionMode, forKey: .permissionMode)
        try container.encode(launchMode, forKey: .launchMode)
        try container.encode(thinkingDepth, forKey: .thinkingDepth)
        try container.encode(command, forKey: .command)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(lastActivityAt, forKey: .lastActivityAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(terminalWindowID, forKey: .terminalWindowID)
        try container.encodeIfPresent(terminalTabIndex, forKey: .terminalTabIndex)
        try container.encode(canSendCommands, forKey: .canSendCommands)
        try container.encode(canTerminate, forKey: .canTerminate)
        try container.encodeIfPresent(renameCommandTemplate, forKey: .renameCommandTemplate)
    }

    static func make(
        id: UUID? = nil,
        origin: SessionOrigin,
        profile: LaunchProfile?,
        displayName: String,
        command: String,
        status: ManagedSessionStatus,
        isPinned: Bool = false,
        sessionID: String? = nil,
        pid: Int32? = nil,
        terminalWindowID: Int? = nil,
        terminalTabIndex: Int? = nil,
        errorMessage: String? = nil,
        summary: String = "",
        summaryStatus: SummaryStatus = .none,
        canSendCommands: Bool = false,
        canTerminate: Bool = true,
        renameCommandTemplate: String? = nil,
        createdAt: Date = Date()
    ) -> ManagedSession {
        let now = Date()
        return ManagedSession(
            id: id ?? UUID(),
            cliKind: profile?.cliKind ?? .claude,
            origin: origin,
            profileID: profile?.id,
            profileName: profile?.name ?? "会话",
            displayName: displayName,
            launchedName: displayName,
            sessionName: displayName,
            sessionID: sessionID,
            pid: pid,
            notes: "",
            summary: summary,
            summaryStatus: summaryStatus,
            workingDirectory: profile?.workingDirectory ?? NSHomeDirectory(),
            model: profile?.model ?? "",
            permissionMode: profile?.permissionMode ?? .default,
            launchMode: profile?.launchMode ?? .standard,
            thinkingDepth: profile?.thinkingDepth ?? .auto,
            command: command,
            createdAt: createdAt,
            updatedAt: now,
            lastActivityAt: now,
            status: status,
            isPinned: isPinned,
            errorMessage: errorMessage,
            terminalWindowID: terminalWindowID,
            terminalTabIndex: terminalTabIndex,
            canSendCommands: canSendCommands,
            canTerminate: canTerminate,
            renameCommandTemplate: renameCommandTemplate
        )
    }
}

extension String {
    func nonEmpty(or fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
