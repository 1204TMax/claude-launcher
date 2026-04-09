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
        case .default: "默认询问"
        case .auto: "自动模式"
        case .acceptEdits: "自动接受编辑"
        case .dontAsk: "仅允许白名单"
        case .bypassPermissions: "跳过权限（危险）"
        case .plan: "规划模式"
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
    case low
    case medium
    case high
    case max

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum ManagedSessionStatus: String, Codable, CaseIterable, Identifiable {
    case launching
    case running
    case idle
    case exited
    case failed
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .launching: "启动中"
        case .running: "运行中"
        case .idle: "空闲"
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

enum GatewayProviderType: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case customGateway
    case bedrock
    case vertex
    case foundry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic 官方"
        case .customGateway: "自定义网关"
        case .bedrock: "AWS Bedrock"
        case .vertex: "Google Vertex"
        case .foundry: "Azure Foundry"
        }
    }
}

enum SessionOrigin: String, Codable, CaseIterable, Identifiable {
    case appLaunched
    case discoveredExternal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appLaunched: "本应用启动"
        case .discoveredExternal: "外部发现"
        }
    }
}

struct GatewayConfig: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var providerType: GatewayProviderType
    var baseURL: String
    var apiKeyReference: String
    var authTokenReference: String
    var createdAt: Date
    var updatedAt: Date

    static func makeDefault() -> GatewayConfig {
        GatewayConfig(
            id: UUID(),
            name: "默认 Anthropic",
            providerType: .anthropic,
            baseURL: "",
            apiKeyReference: UUID().uuidString,
            authTokenReference: UUID().uuidString,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

struct LaunchProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var workingDirectory: String
    var additionalDirectories: [String]
    var batchCount: Int
    var permissionMode: PermissionMode
    var launchMode: LaunchMode
    var thinkingDepth: ThinkingDepth
    var model: String
    var gatewayConfigID: UUID?
    var startupRenameTemplate: String
    var startupMessage: String
    var appendSystemPrompt: String
    var createdAt: Date
    var updatedAt: Date

    static let suggestedModels = [
        "default",
        "best",
        "sonnet",
        "opus",
        "haiku",
        "sonnet[1m]",
        "opus[1m]",
        "opusplan"
    ]

    static func makeDefault() -> LaunchProfile {
        LaunchProfile(
            id: UUID(),
            name: "新配置",
            workingDirectory: NSHomeDirectory(),
            additionalDirectories: [],
            batchCount: 1,
            permissionMode: .default,
            launchMode: .standard,
            thinkingDepth: .medium,
            model: "sonnet",
            gatewayConfigID: nil,
            startupRenameTemplate: "{{profile}} {{index}}",
            startupMessage: "",
            appendSystemPrompt: "",
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
    var gatewayName: String?
    var command: String
    var createdAt: Date
    var updatedAt: Date
    var lastActivityAt: Date
    var lastObservedAt: Date?
    var status: ManagedSessionStatus
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
        gatewayName: String?,
        displayName: String,
        command: String,
        status: ManagedSessionStatus,
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
            profileName: profile?.name ?? "外部会话",
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
            thinkingDepth: profile?.thinkingDepth ?? .medium,
            gatewayName: gatewayName,
            command: command,
            createdAt: createdAt,
            updatedAt: now,
            lastActivityAt: now,
            lastObservedAt: now,
            status: status,
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
