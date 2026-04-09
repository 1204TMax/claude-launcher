import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OverviewBar()
            Divider()
            HStack(spacing: 0) {
                LeftConfigColumn()
                    .frame(width: 320)
                Divider()
                SessionsColumn()
                    .frame(minWidth: 420)
                Divider()
                SessionDetailColumn()
                    .frame(minWidth: 360)
            }
        }
        .alert("操作失败", isPresented: Binding(get: {
            appModel.errorMessage != nil
        }, set: { newValue in
            if !newValue {
                appModel.errorMessage = nil
            }
        })) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }
}

private struct OverviewBar: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Text("Claude Code 工作台")
                .font(.title3.weight(.semibold))

            Spacer()

            OverviewBadge(title: "Live", value: "\(appModel.allSessions.count)")
            OverviewBadge(title: "运行中", value: "\(appModel.runningSessionCount)")
            OverviewBadge(title: "空闲", value: "\(appModel.idleSessionCount)")
            OverviewBadge(title: "上次同步", value: appModel.latestObservedTimeText)

            Button(action: appModel.refreshPreview) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct OverviewBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LeftConfigColumn: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileListCard
                if let profile = appModel.selectedProfile {
                    profileConfigCard(profile)
                    launchCard
                    advancedCard(profile)
                } else {
                    ContentUnavailableView("未选择配置", systemImage: "sidebar.left")
                }
            }
            .padding(16)
        }
    }

    private var profileListCard: some View {
        GroupBox("配置列表") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(action: appModel.createProfile) {
                        Label("新建配置", systemImage: "plus")
                    }
                    Button(action: appModel.duplicateSelectedProfile) {
                        Label("复制", systemImage: "square.on.square")
                    }
                }
                Button(role: .destructive, action: appModel.deleteSelectedProfile) {
                    Label("删除配置", systemImage: "trash")
                }

                List(selection: Binding(
                    get: { appModel.selectedProfileID },
                    set: { appModel.selectProfile($0) }
                )) {
                    ForEach(appModel.profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.workingDirectory)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("默认启动数：\(profile.batchCount)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(profile.id)
                    }
                }
                .frame(minHeight: 180)
            }
            .padding(.top, 8)
        }
    }

    private func profileConfigCard(_ profile: LaunchProfile) -> some View {
        GroupBox("配置设置") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("配置名称", text: binding(profile, \.name))
                HStack {
                    TextField("工作目录", text: binding(profile, \.workingDirectory))
                    Button("选择目录", action: appModel.browseWorkingDirectory)
                }
                Picker("权限模式", selection: binding(profile, \.permissionMode)) {
                    ForEach(PermissionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("启动模式", selection: binding(profile, \.launchMode)) {
                    ForEach(LaunchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("思考深度", selection: binding(profile, \.thinkingDepth)) {
                    ForEach(ThinkingDepth.allCases) { depth in
                        Text(depth.displayName).tag(depth)
                    }
                }
                Picker("模型", selection: binding(profile, \.model)) {
                    ForEach(LaunchProfile.suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
                TextField("自定义模型 ID", text: binding(profile, \.model))
            }
            .textFieldStyle(.roundedBorder)
            .pickerStyle(.menu)
            .padding(.top, 8)
        }
    }

    private var launchCard: some View {
        GroupBox("批量启动") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("数量", text: Binding(
                        get: { appModel.launchCountInput },
                        set: { appModel.updateLaunchCountInput($0) }
                    ))
                    .frame(width: 72)
                    .textFieldStyle(.roundedBorder)
                    Button(action: appModel.decreaseLaunchCount) {
                        Image(systemName: "minus.circle")
                    }
                    Button(action: appModel.increaseLaunchCount) {
                        Image(systemName: "plus.circle")
                    }
                    Spacer()
                    Button(action: appModel.launchSelectedProfile) {
                        Text(appModel.launchButtonTitle)
                    }
                    .buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("将要创建")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appModel.sessionNamePreviewText.isEmpty ? "暂无预览" : appModel.sessionNamePreviewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        }
    }

    private func advancedCard(_ profile: LaunchProfile) -> some View {
        DisclosureGroup("高级") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("附加上下文目录（逗号分隔）", text: Binding(
                    get: { profile.additionalDirectories.joined(separator: ", ") },
                    set: { value in
                        appModel.updateSelectedProfile {
                            $0.additionalDirectories = value
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                    }
                ))
                TextField("会话命名模板", text: binding(profile, \.startupRenameTemplate), prompt: Text("{{profile}} {{index}}"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("附加系统提示词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: binding(profile, \.appendSystemPrompt))
                        .frame(minHeight: 70)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("启动后首条消息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: binding(profile, \.startupMessage))
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                }
                GroupBox("命令预览") {
                    Text(appModel.commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 8)
        }
        .padding(.top, 4)
    }

    private func binding<Value>(_ profile: LaunchProfile, _ keyPath: WritableKeyPath<LaunchProfile, Value>) -> Binding<Value> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                appModel.updateSelectedProfile { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

private struct SessionsColumn: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当前会话")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("仅显示 Live")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appModel.allSessions.isEmpty {
                ContentUnavailableView("当前没有发现 Claude Code 会话", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { appModel.selectedSessionID },
                    set: { appModel.selectSession($0) }
                )) {
                    ForEach(appModel.allSessions) { session in
                        SessionCardRow(session: session)
                            .tag(session.id)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
    }
}

private struct SessionCardRow: View {
    let session: ManagedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(session.displayName)
                    .font(.headline)
                Spacer()
                Text(session.status.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(session.summary.isEmpty ? defaultSummary : session.summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(session.origin.displayName)
                if let observed = session.lastObservedAt {
                    Text("·")
                    Text(relativeTimeText(for: observed))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(session.workingDirectory)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var defaultSummary: String {
        session.origin == .discoveredExternal ? "外部发现的实时 Claude Code 会话" : "尚未生成摘要"
    }

    private func relativeTimeText(for date: Date) -> String {
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        if seconds < 60 { return "\(seconds) 秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        return "\(hours) 小时前"
    }
}

private struct SessionDetailColumn: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var renameDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("会话详情")
                    .font(.title3.weight(.semibold))

                if let session = appModel.selectedSession {
                    identityCard(session)
                    contextCard(session)
                    controlCard(session)
                    technicalCard(session)
                } else {
                    ContentUnavailableView("请选择一个会话查看详情", systemImage: "sidebar.right")
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(16)
        }
        .onAppear {
            if renameDraft.isEmpty {
                renameDraft = appModel.selectedSession?.displayName ?? ""
            }
        }
        .onChange(of: appModel.selectedSessionID) { _ in
            renameDraft = appModel.selectedSession?.displayName ?? ""
        }
    }

    private func identityCard(_ session: ManagedSession) -> some View {
        GroupBox("身份") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("会话名称", text: Binding(
                        get: { renameDraft },
                        set: { renameDraft = $0 }
                    ))
                    .onSubmit {
                        appModel.updateSelectedSessionName(renameDraft)
                    }
                    Button("应用改名") {
                        appModel.updateSelectedSessionName(renameDraft)
                    }
                    .buttonStyle(.bordered)
                }
                detailRow("来源", session.origin.displayName)
                detailRow("状态", session.status.displayName)
                if let claudeName = session.claudeSessionName {
                    detailRow("Claude 当前名称", claudeName)
                }
                if let observed = session.lastObservedAt {
                    detailRow("最近活动", observed.formatted(date: .abbreviated, time: .standard))
                }
                detailRow("工作目录", session.workingDirectory)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 8)
        }
    }

    private func contextCard(_ session: ManagedSession) -> some View {
        GroupBox("工作语境") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("说明")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { session.notes },
                        set: { appModel.updateSelectedSessionNotes($0) }
                    ))
                    .frame(minHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("摘要")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("生成摘要", action: appModel.generateSummaryPlaceholder)
                    }
                    TextEditor(text: .constant(session.summary.isEmpty ? (session.origin == .discoveredExternal ? "外部发现的实时 Claude Code 会话。" : "尚未生成摘要。") : session.summary))
                        .frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
                }
            }
            .padding(.top, 8)
        }
    }

    private func controlCard(_ session: ManagedSession) -> some View {
        GroupBox("控制") {
            HStack {
                Button("关闭会话", action: appModel.terminateSelectedSession)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canTerminate)
                Button("归档", action: appModel.archiveSelectedSession)
                    .disabled(session.origin == .discoveredExternal)
            }
            .padding(.top, 8)
        }
    }

    private func technicalCard(_ session: ManagedSession) -> some View {
        DisclosureGroup("技术细节") {
            VStack(alignment: .leading, spacing: 8) {
                if let pid = session.pid {
                    detailRow("PID", String(pid))
                }
                if let sessionID = session.claudeSessionID {
                    detailRow("Claude SessionID", sessionID)
                }
                if let gateway = session.gatewayName {
                    detailRow("网关", gateway)
                }
                Text(session.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 8)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}
