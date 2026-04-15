import SwiftUI

private enum ProfileEditorMode: Equatable {
    case rename(LaunchProfile.ID)
    case saveAs(LaunchProfile.ID)
}

private struct ProfileMenuAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct LaunchWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isProfilePanelExpanded = false
    @State private var profileEditorMode: ProfileEditorMode?
    @State private var draftProfileName = ""
    @State private var showDeleteConfirmation = false
    @State private var deletingProfileID: LaunchProfile.ID?
    @State private var profileMenuAnchorFrame: CGRect = .zero
    @State private var hoveredProfileID: LaunchProfile.ID?

    private var selectedProfile: LaunchProfile? { appModel.selectedProfile }
    private let trailingControlWidth: CGFloat = 168

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                            .padding(.bottom, 24)
                        content
                    }
                    .frame(maxWidth: 408)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 138)
                }
                .frame(maxWidth: .infinity)
            }

            if isProfilePanelExpanded {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                            closeProfilePanel()
                        }
                    }
                    .zIndex(20)

                profileInlinePanel
                    .frame(width: 420, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(LauncherTheme.border.opacity(0.82), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: profileMenuAnchorFrame.minX, y: profileMenuAnchorFrame.maxY + 8)
                    .zIndex(30)
            }
        }
        .coordinateSpace(name: "LaunchWorkspace")
        .safeAreaInset(edge: .bottom) {
            launchButtonBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background {
                    LauncherBottomBarBackground()
                }
        }
        .launcherPanelBackground()
        .onPreferenceChange(ProfileMenuAnchorPreferenceKey.self) { frame in
            if frame != .zero {
                profileMenuAnchorFrame = frame
            }
        }
        .alert("删除配置？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                deletingProfileID = nil
            }
            Button("删除", role: .destructive) {
                if let deletingProfileID {
                    appModel.deleteProfile(deletingProfileID)
                    self.deletingProfileID = nil
                    profileEditorMode = nil
                }
            }
        } message: {
            Text("删除后会自动切换到其他配置。")
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("启动设置")
                .font(.launcherTitle)
                .foregroundStyle(LauncherTheme.primaryText)
            Text("设置 Claude Code 启动参数")
                .font(.launcherMeta)
                .foregroundStyle(LauncherTheme.secondaryText)
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            configurationCard
            advancedToggle
            if selectedProfile?.advancedSettingsEnabled ?? false {
                advancedPanel
            }
        }
    }

    private var configurationCard: some View {
        LauncherSurfaceCard(cornerRadius: 16) {
            VStack(spacing: 0) {
                configurationRow
                inlineDivider
                modelRow
            }
        }
    }

    private var configurationRow: some View {
        settingLine(title: "配置") {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                    isProfilePanelExpanded.toggle()
                    if !isProfilePanelExpanded {
                        profileEditorMode = nil
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedProfile?.name ?? "未选择配置")
                        .font(.launcherBody)
                        .foregroundStyle(LauncherTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LauncherTheme.secondaryText)
                        .rotationEffect(.degrees(isProfilePanelExpanded ? 180 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .background(LauncherTheme.softFill.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LauncherTheme.border.opacity(0.95), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ProfileMenuAnchorPreferenceKey.self, value: proxy.frame(in: .named("LaunchWorkspace")))
                }
            )
        }
    }

    private var modelRow: some View {
        settingLine(title: "模型") {
            compactMenu(selection: Binding(
                get: { selectedProfile?.model ?? LaunchProfile.modelOptions[1].id },
                set: { value in appModel.updateSelectedProfile { $0.model = value } }
            ), items: LaunchProfile.modelOptions.map(\.id), minWidth: 196) { id in
                if let option = LaunchProfile.modelOptions.first(where: { $0.id == id }) {
                    return "\(option.title)（\(option.subtitle)）"
                }
                return id
            }
        }
    }

    private var profileInlinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                appModel.createProfile()
                profileEditorMode = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("添加新配置")
                        .font(.launcherMeta)
                }
                .foregroundStyle(LauncherTheme.blueTint)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(LauncherTheme.border.opacity(0.72))
                .frame(height: 1)

            VStack(spacing: 6) {
                ForEach(appModel.profiles) { profile in
                    profileInlineRow(profile)
                }
            }

            if profileEditorMode != nil {
                Rectangle()
                    .fill(LauncherTheme.border.opacity(0.72))
                    .frame(height: 1)
                    .padding(.top, 2)
                profileInlineEditor
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(LauncherTheme.softFill.opacity(0.28))
    }

    private var profileInlineEditor: some View {
        HStack(spacing: 8) {
            LauncherTextFieldContainer(cornerRadius: 10, minHeight: 36) {
                TextField(profileEditorPlaceholder, text: $draftProfileName)
                    .textFieldStyle(.plain)
                    .font(.launcherBody)
            }

            Button("取消") {
                profileEditorMode = nil
                draftProfileName = ""
            }
            .buttonStyle(LauncherGhostButtonStyle())

            Button("确定") {
                commitProfileEditor()
            }
            .buttonStyle(LauncherGhostButtonStyle())
            .disabled(draftProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var profileEditorPlaceholder: String {
        switch profileEditorMode {
        case .saveAs:
            return "输入新配置名称"
        case .rename:
            return "输入配置名称"
        case nil:
            return "输入配置名称"
        }
    }

    private var inlineDivider: some View {
        Divider()
            .overlay(LauncherTheme.border.opacity(0.42))
            .padding(.horizontal, 22)
    }

    private var launchButtonBar: some View {
        mergedLaunchButton
            .frame(maxWidth: 408)
            .frame(maxWidth: .infinity)
    }

    private var mergedLaunchButton: some View {
        HStack(spacing: 0) {
            Button(action: appModel.decreaseLaunchCount) {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 62, height: 54)
                    .foregroundStyle(appModel.resolvedLaunchCount <= 1 ? Color.white.opacity(0.18) : Color.white.opacity(0.54))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(appModel.resolvedLaunchCount <= 1)

            Button(action: appModel.launchSelectedProfile) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.56))
                    Text("启动")
                        .font(.system(size: 15, weight: .medium))
                    Text("\(appModel.resolvedLaunchCount)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("个会话")
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(Color.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
            }

            Button(action: appModel.increaseLaunchCount) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 62, height: 54)
                    .foregroundStyle(Color.white.opacity(0.54))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(LauncherTheme.ctaBlack)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: .black.opacity(0.13), radius: 14, x: 0, y: 6)
    }

    private var advancedToggle: some View {
        HStack(spacing: 12) {
            Text("高级设置")
                .font(.launcherBody)
                .foregroundStyle(LauncherTheme.secondaryText)
            Spacer()
            switchControl(isOn: selectedProfile?.advancedSettingsEnabled ?? false) { isOn in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    appModel.updateSelectedProfile {
                        $0.advancedSettingsEnabled = isOn
                        if !isOn {
                            $0.startupRenameEnabled = false
                        }
                    }
                }
            }
        }
    }

    private var advancedPanel: some View {
        LauncherSurfaceCard(cornerRadius: 16) {
            VStack(spacing: 0) {
                workdirSection
                divider
                autoRenameSection
                divider
                bringFilesSection
                divider
                permissionSection
                divider
                thinkingDepthSection
                divider
                terminalFontSection
                divider
                themeSection
            }
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)),
            removal: .opacity.combined(with: .offset(y: -4))
        ))
    }

    private var workdirSection: some View {
        fieldSection(title: "工作目录") {
            if let profile = selectedProfile {
                HStack(spacing: 8) {
                    LauncherTextFieldContainer {
                        TextField("选择目录", text: binding(profile, \.workingDirectory))
                            .textFieldStyle(.plain)
                            .font(.launcherBody)
                            .foregroundStyle(LauncherTheme.primaryText)
                    }
                    Button("选择") { appModel.browseWorkingDirectory() }
                        .buttonStyle(LauncherGhostButtonStyle())
                }
            }
        }
    }

    private var autoRenameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("自定义会话名称")
                    .font(.launcherBodyStrong)
                    .foregroundStyle(LauncherTheme.primaryText)
                Spacer()
                switchControl(isOn: selectedProfile?.startupRenameEnabled ?? false) { isOn in
                    appModel.updateSelectedProfile { $0.startupRenameEnabled = isOn }
                }
            }
            if let profile = selectedProfile, profile.startupRenameEnabled {
                LauncherTextFieldContainer {
                    TextField("输入自定义会话名称", text: binding(profile, \.startupRenameTemplate))
                        .textFieldStyle(.plain)
                        .font(.launcherBody)
                        .foregroundStyle(LauncherTheme.primaryText)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var thinkingDepthSection: some View {
        settingLine(title: "思考深度", help: "思考越深入，回复时间越长，消耗token越多。") {
            compactMenu(selection: Binding(
                get: { selectedProfile?.thinkingDepth ?? .auto },
                set: { value in appModel.updateSelectedProfile { $0.thinkingDepth = value } }
            ), items: ThinkingDepth.launchOptions, minWidth: trailingControlWidth) { $0.displayName }
        }
    }

    private var permissionSection: some View {
        settingLine(title: "权限") {
            if let profile = selectedProfile {
                compactMenu(selection: binding(profile, \.permissionMode), items: PermissionMode.launchOptions, minWidth: trailingControlWidth) { $0.displayName }
            }
        }
    }

    private var bringFilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("启动时带入文件")
                    .font(.launcherBodyStrong)
                    .foregroundStyle(LauncherTheme.primaryText)
                Spacer()
                Button {
                    appModel.browseContextFiles()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                        Text("选择文件")
                    }
                    .font(.launcherMeta)
                    .foregroundStyle(LauncherTheme.blueTint)
                }
                .buttonStyle(.plain)
            }
            if let profile = selectedProfile, !profile.contextFilePaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.contextFilePaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Text("@\((path as NSString).lastPathComponent)")
                                .font(.launcherMeta)
                                .foregroundStyle(LauncherTheme.secondaryText)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                appModel.removeContextFile(path)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(LauncherTheme.tertiaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(LauncherTheme.softFill.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var terminalFontSection: some View {
        HStack(alignment: .center, spacing: 18) {
            Text("字体大小")
                .font(.launcherBodyStrong)
                .foregroundStyle(LauncherTheme.primaryText)
            Spacer(minLength: 16)
            if let profile = selectedProfile {
                HStack(spacing: 8) {
                    compactMenu(selection: binding(profile, \.terminalFontPreference), items: Array(TerminalFontPreference.allCases), minWidth: 112) { $0.displayName }
                    if profile.terminalFontPreference == .custom {
                        LauncherTextFieldContainer {
                            TextField("字号", text: binding(profile, \.customTerminalFontSize))
                                .textFieldStyle(.plain)
                                .font(.launcherBody)
                                .foregroundStyle(LauncherTheme.primaryText)
                                .frame(width: 48)
                        }
                    }
                }
                .frame(width: profile.terminalFontPreference == .custom ? 204 : trailingControlWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private var themeSection: some View {
        settingLine(title: "主题") {
            if let profile = selectedProfile {
                compactMenu(selection: binding(profile, \.themePreference), items: Array(ThemePreference.allCases), minWidth: trailingControlWidth) { $0.displayName }
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(LauncherTheme.border.opacity(0.42))
            .padding(.horizontal, 22)
    }

    private func settingLine<Content: View>(title: String, help: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.launcherBodyStrong)
                    .foregroundStyle(LauncherTheme.primaryText)
                if let help {
                    HelpTooltip(text: help)
                }
            }
            Spacer(minLength: 16)
            content()
                .frame(width: trailingControlWidth, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
    }

    private func profileInlineRow(_ profile: LaunchProfile) -> some View {
        let isCurrent = appModel.selectedProfileID == profile.id
        let isHovering = hoveredProfileID == profile.id
        return HStack(alignment: .center, spacing: 8) {
            Button {
                appModel.selectProfile(profile.id)
                closeProfilePanel()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isCurrent ? LauncherTheme.blueTint : LauncherTheme.tertiaryText)
                        .opacity(isCurrent ? 1 : 0)
                        .frame(width: 14)
                    Text(profile.name)
                        .font(.launcherBody)
                        .foregroundStyle(isCurrent ? LauncherTheme.blueTint : LauncherTheme.primaryText)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                if isCurrent {
                    inlineAction("复制") {
                        appModel.saveProfileAs(profile.id, name: "\(profile.name) 副本")
                        closeProfilePanel()
                    }
                }

                inlineAction("重命名") {
                    profileEditorMode = .rename(profile.id)
                    draftProfileName = profile.name
                }

                inlineAction("删除", isDestructive: true) {
                    deletingProfileID = profile.id
                    showDeleteConfirmation = true
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground(isCurrent: isCurrent, isHovering: isHovering))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowBorderColor(isCurrent: isCurrent, isHovering: isHovering), lineWidth: isCurrent || isHovering ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            if hovering {
                hoveredProfileID = profile.id
            } else if hoveredProfileID == profile.id {
                hoveredProfileID = nil
            }
        }
    }

    private func inlineAction(_ title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.launcherMeta)
                .foregroundStyle(isDestructive ? Color.red : LauncherTheme.blueTint)
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(isCurrent: Bool, isHovering: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isCurrent ? LauncherTheme.blueTint.opacity(0.16) : (isHovering ? Color.black.opacity(0.07) : Color.clear))
    }

    private func rowBorderColor(isCurrent: Bool, isHovering: Bool) -> Color {
        if isCurrent {
            return LauncherTheme.blueTint.opacity(0.9)
        }
        if isHovering {
            return Color.black.opacity(0.14)
        }
        return .clear
    }

    private func commitProfileEditor() {
        guard let profileEditorMode else { return }
        switch profileEditorMode {
        case .rename(let profileID):
            appModel.renameProfile(profileID, to: draftProfileName)
        case .saveAs(let profileID):
            appModel.saveProfileAs(profileID, name: draftProfileName)
        }
        closeProfilePanel()
        draftProfileName = ""
    }

    private func closeProfilePanel() {
        isProfilePanelExpanded = false
        profileEditorMode = nil
        hoveredProfileID = nil
    }

    private func fieldSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.launcherBodyStrong)
                .foregroundStyle(LauncherTheme.primaryText)
            content()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func switchControl(isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Button {
            onChange(!isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? LauncherTheme.ctaBlack : LauncherTheme.border.opacity(0.95))
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func compactMenu<T: Hashable>(selection: Binding<T>, items: [T], minWidth: CGFloat, label: @escaping (T) -> String) -> some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button {
                    selection.wrappedValue = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection.wrappedValue == item ? "checkmark" : "")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 14)
                        Text(label(item))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.vertical, 3)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label(selection.wrappedValue))
                    .font(.launcherBody)
                    .foregroundStyle(LauncherTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LauncherTheme.secondaryText)
            }
            .frame(minWidth: minWidth, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .background(LauncherTheme.softFill.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.95), lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
    }

    private func stepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LauncherTheme.secondaryText)
                .frame(width: 28, height: 28)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func textEditor(text: Binding<String>, minHeight: CGFloat, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.launcherBody)
            .foregroundStyle(LauncherTheme.primaryText)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(LauncherTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LauncherTheme.border.opacity(0.85), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.launcherBody)
                        .foregroundStyle(LauncherTheme.tertiaryText.opacity(0.55))
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
            }
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

private struct HelpTooltip: View {
    enum Placement {
        case above
        case below
    }

    let text: String
    let placement: Placement
    @State private var isHovering = false

    init(text: String, placement: Placement = .below) {
        self.text = text
        self.placement = placement
    }

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(LauncherTheme.tertiaryText)
            .frame(width: 18, height: 18, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .popover(isPresented: $isHovering, attachmentAnchor: .rect(.bounds), arrowEdge: placement == .above ? .bottom : .top) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LauncherTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color.white)
            }
    }
}
