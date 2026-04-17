import Foundation

enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case `default`
    case auto
    case acceptEdits
    case dontAsk
    case bypassPermissions
    case plan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "每次询问"
        case .auto: "自动模式"
        case .acceptEdits: "允许编辑"
        case .dontAsk: "不询问"
        case .bypassPermissions: "最大权限"
        case .plan: "只读模式"
        }
    }

    var commandText: String {
        switch self {
        case .default:
            return "--permission-mode default"
        case .acceptEdits:
            return "--permission-mode acceptEdits"
        case .plan:
            return "--permission-mode plan"
        case .auto:
            return "--permission-mode auto"
        case .bypassPermissions:
            return "--dangerously-skip-permissions"
        case .dontAsk:
            return "--permission-mode dontAsk"
        }
    }

    var helpText: String {
        switch self {
        case .default:
            return "首次使用工具时询问确认"
        case .acceptEdits:
            return "自动接受文件修改，其余仍询问"
        case .plan:
            return "仅分析规划，不写入任何文件"
        case .auto:
            return "自动批准所有操作（预览版）"
        case .bypassPermissions:
            return "跳过所有权限检查，完全自动执行"
        case .dontAsk:
            return "仅允许运行白名单工具"
        }
    }

    static let launchOptions: [PermissionMode] = [.default, .acceptEdits, .plan, .auto, .bypassPermissions]
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

    static let launchOptions: [ThinkingDepth] = [.auto, .low, .medium, .high, .xhigh, .max]
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

struct LaunchModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

struct LaunchProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var workingDirectory: String
    var additionalDirectories: [String]
    var contextFilePaths: [String]
    var batchCount: Int
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
        case name
        case workingDirectory
        case additionalDirectories
        case contextFilePaths
        case batchCount
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
        name: String,
        workingDirectory: String,
        additionalDirectories: [String],
        contextFilePaths: [String],
        batchCount: Int,
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
        self.name = name
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.contextFilePaths = contextFilePaths
        self.batchCount = batchCount
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
        name = try container.decode(String.self, forKey: .name)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        additionalDirectories = try container.decodeIfPresent([String].self, forKey: .additionalDirectories) ?? []
        contextFilePaths = try container.decodeIfPresent([String].self, forKey: .contextFilePaths) ?? []
        batchCount = try container.decodeIfPresent(Int.self, forKey: .batchCount) ?? 1
        permissionMode = try container.decodeIfPresent(PermissionMode.self, forKey: .permissionMode) ?? .default
        launchMode = try container.decodeIfPresent(LaunchMode.self, forKey: .launchMode) ?? .standard
        thinkingDepth = try container.decodeIfPresent(ThinkingDepth.self, forKey: .thinkingDepth) ?? .auto
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "sonnet[1m]"
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

    static let modelOptions = [
        LaunchModelOption(id: "haiku", title: "Haiku 4.5", subtitle: "轻量高速"),
        LaunchModelOption(id: "sonnet[1m]", title: "Sonnet 4.6", subtitle: "日常主力"),
        LaunchModelOption(id: "opus[1m]", title: "Opus 4.7", subtitle: "复杂任务")
    ]

    static let suggestedModels = modelOptions.map(\.id)

    static func makeDefault() -> LaunchProfile {
        LaunchProfile(
            id: UUID(),
            name: "新配置",
            workingDirectory: NSHomeDirectory(),
            additionalDirectories: [],
            contextFilePaths: [],
            batchCount: 1,
            permissionMode: .default,
            launchMode: .standard,
            thinkingDepth: .auto,
            model: "sonnet[1m]",
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
    var origin: SessionOrigin
    var profileID: UUID?
    var profileName: String
    var displayName: String
    var launchedName: String
    var claudeSessionName: String?
    var claudeSessionID: String?
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

    static func make(
        id: UUID? = nil,
        origin: SessionOrigin,
        profile: LaunchProfile?,
        displayName: String,
        command: String,
        status: ManagedSessionStatus,
        isPinned: Bool = false,
        claudeSessionID: String? = nil,
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
            origin: origin,
            profileID: profile?.id,
            profileName: profile?.name ?? "会话",
            displayName: displayName,
            launchedName: displayName,
            claudeSessionName: displayName,
            claudeSessionID: claudeSessionID,
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
