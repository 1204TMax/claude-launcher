import SwiftUI

private struct SessionMenuOverlayContext {
    let item: SessionListItem
    let anchorFrame: CGRect
}

struct SessionsWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var renamingItem: SessionListItem?
    @State private var draftSessionName = ""
    @State private var openMenuItemID: SessionListItem.ID?
    @State private var menuAnchorFrame: CGRect = .zero
    @State private var showScrollToast = false

    private var filteredSessions: [SessionListItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return appModel.sessionListItems }
        return appModel.sessionListItems.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            $0.cwd.localizedCaseInsensitiveContains(keyword) ||
            ($0.sessionID ?? "").localizedCaseInsensitiveContains(keyword)
        }
    }

    private var openMenuContext: SessionMenuOverlayContext? {
        guard let openMenuItemID,
              let item = filteredSessions.first(where: { $0.id == openMenuItemID }) else {
            return nil
        }
        return SessionMenuOverlayContext(item: item, anchorFrame: menuAnchorFrame)
    }

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 24) {
                sidebar
                    .frame(width: 368)
                contentPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)

            if let context = openMenuContext {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openMenuItemID = nil
                    }
                    .zIndex(20)

                sessionMenuOverlay(for: context.item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: context.anchorFrame.maxX - 124, y: context.anchorFrame.maxY + 6)
                    .zIndex(30)
            }
        }
        .launcherPanelBackground()
        .coordinateSpace(name: "SessionsWorkspace")
        .task {
            appModel.reloadDiscoveredSessions()
        }
        .sheet(item: $renamingItem) { item in
            renameSheet(for: item)
        }
    }

    private var sidebar: some View {
        LauncherSurfaceCard(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 18) {
                searchBar

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("会话记录")
                            .font(.launcherLabel)
                            .tracking(1.1)
                            .foregroundStyle(LauncherTheme.tertiaryText)
                        Button {
                            appModel.reloadDiscoveredSessions()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LauncherTheme.secondaryText)
                                .frame(width: 24, height: 24)
                                .background(LauncherTheme.softFill)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("\(filteredSessions.count)")
                            .font(.launcherMini)
                            .foregroundStyle(LauncherTheme.tertiaryText)
                            .monospacedDigit()
                            .frame(minWidth: 28, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)

                    if appModel.isDiscoveringSessions && filteredSessions.isEmpty {
                        loadingListCard
                    } else if filteredSessions.isEmpty {
                        emptyListCard
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredSessions) { session in
                                    sessionRow(session)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            .padding(18)
        }
    }

    private var searchBar: some View {
        LauncherTextFieldContainer {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LauncherTheme.tertiaryText)
                TextField("输入搜索的会话名称", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.launcherBody)
                Spacer()
            }
        }
    }

    private var emptyListCard: some View {
        LauncherSurfaceCard(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("暂无会话")
                    .font(.launcherBodyStrong)
                    .foregroundStyle(LauncherTheme.primaryText)
                Text("本机 Claude Code 会话会显示在这里。")
                    .font(.launcherMeta)
                    .foregroundStyle(LauncherTheme.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadingListCard: some View {
        LauncherSurfaceCard(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("正在同步会话")
                    .font(.launcherBodyStrong)
                    .foregroundStyle(LauncherTheme.primaryText)
                Text("窗口可先使用，列表稍后更新。")
                    .font(.launcherMeta)
                    .foregroundStyle(LauncherTheme.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sessionRow(_ session: SessionListItem) -> some View {
        SessionRowView(
            item: session,
            isSelected: appModel.isSessionListItemSelected(session),
            isMenuPresented: openMenuItemID == session.id,
            onSelect: {
                openMenuItemID = nil
                appModel.selectSessionListItem(session)
            },
            onDismissMenu: {
                openMenuItemID = nil
            },
            onToggleMenu: { anchorFrame in
                menuAnchorFrame = anchorFrame
                openMenuItemID = openMenuItemID == session.id ? nil : session.id
            },
            onTogglePinned: {
                openMenuItemID = nil
                appModel.setPinned(for: session, pinned: !session.isPinned)
            },
            onRename: {
                openMenuItemID = nil
                renamingItem = session
                draftSessionName = session.title
            },
            onReopen: {
                openMenuItemID = nil
                appModel.reopenSessionListItem(session)
            },
            onDelete: {
                openMenuItemID = nil
                appModel.deleteSessionListItem(session)
            }
        )
    }

    private var contentPane: some View {
        LauncherSurfaceCard(cornerRadius: 18) {
            Group {
                if appModel.selectedDiscoveredSession != nil {
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    LazyVStack(spacing: 18) {
                                        if appModel.selectedTranscriptMessages.isEmpty {
                                            emptyContent
                                        } else {
                                            ForEach(appModel.selectedTranscriptMessages) { message in
                                                contentMessageCard(message)
                                                    .id(message.id)
                                                    .onAppear {
                                                        appModel.loadMoreTranscriptHistoryIfNeeded(triggerMessageID: message.id)
                                                    }
                                            }
                                        }
                                    }
                                    .padding(28)
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }
                                .onAppear {
                                    scrollToBottom(proxy: proxy, animated: false)
                                    showScrollToastBriefly()
                                }
                                .onChange(of: appModel.selectedDiscoveredSessionID) { _ in
                                    scrollToBottom(proxy: proxy, animated: false)
                                    showScrollToastBriefly()
                                }
                                .onChange(of: appModel.selectedTranscriptMessages.last?.id) { _ in
                                    scrollToBottom(proxy: proxy, animated: false)
                                }
                            }
                        }

                        if showScrollToast {
                            Text("已自动定位到最近消息")
                                .font(.launcherMeta)
                                .foregroundStyle(LauncherTheme.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(LauncherTheme.border.opacity(0.8), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                                .padding(.top, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("选择一个会话")
                            .font(.launcherBodyStrong)
                            .foregroundStyle(LauncherTheme.primaryText)
                        Text("右侧只展示该会话的真实对话内容。")
                            .font(.launcherMeta)
                            .foregroundStyle(LauncherTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Text("暂无可展示的对话内容")
                .font(.launcherBodyStrong)
                .foregroundStyle(LauncherTheme.primaryText)
            Text("当前 transcript 中没有可直接渲染的用户/助手文本消息。")
                .font(.launcherMeta)
                .foregroundStyle(LauncherTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func contentMessageCard(_ message: ClaudeTranscriptMessage) -> some View {
        let isUser = message.role == .user
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
            Text(message.text)
                .font(.launcherBody)
                .foregroundStyle(LauncherTheme.primaryText)
                .lineSpacing(5)
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 680, alignment: isUser ? .trailing : .leading)
                .background(isUser ? LauncherTheme.blueSoft.opacity(0.9) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(LauncherTheme.border.opacity(0.72), lineWidth: 1)
                )

            if let timestamp = message.timestamp {
                Text(formattedDateText(for: timestamp))
                    .font(.launcherMeta)
                    .foregroundStyle(LauncherTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = appModel.selectedTranscriptMessages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func showScrollToastBriefly() {
        showScrollToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showScrollToast = false
            }
        }
    }

    private func sessionMenuOverlay(for item: SessionListItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            menuAction(item.isPinned ? "取消置顶" : "置顶") {
                openMenuItemID = nil
                appModel.setPinned(for: item, pinned: !item.isPinned)
            }

            menuAction("重命名") {
                openMenuItemID = nil
                renamingItem = item
                draftSessionName = item.title
            }

            if item.isClosed {
                menuAction("重新打开") {
                    openMenuItemID = nil
                    appModel.reopenSessionListItem(item)
                }
            }

            Rectangle()
                .fill(LauncherTheme.border.opacity(0.9))
                .frame(height: 1)
                .padding(.vertical, 2)

            menuAction("删除", isDestructive: true) {
                openMenuItemID = nil
                appModel.deleteSessionListItem(item)
            }
        }
        .padding(7)
        .frame(width: 124, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LauncherTheme.border.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private func menuAction(_ title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.launcherMeta)
                .foregroundStyle(isDestructive ? Color.red : LauncherTheme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func renameSheet(for item: SessionListItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名会话")
                .font(.launcherBodyStrong)
                .foregroundStyle(LauncherTheme.primaryText)

            LauncherTextFieldContainer {
                TextField("输入新的会话名称", text: $draftSessionName)
                    .textFieldStyle(.plain)
                    .font(.launcherBody)
            }

            HStack {
                Spacer()
                Button("取消") {
                    renamingItem = nil
                }
                .buttonStyle(LauncherGhostButtonStyle())

                Button("确定") {
                    appModel.renameSessionListItem(item, to: draftSessionName)
                    renamingItem = nil
                }
                .buttonStyle(LauncherPrimaryButtonStyle())
                .frame(width: 120)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func formattedDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct SessionRowView: View {
    let item: SessionListItem
    let isSelected: Bool
    let isMenuPresented: Bool
    let onSelect: () -> Void
    let onDismissMenu: () -> Void
    let onToggleMenu: (CGRect) -> Void
    let onTogglePinned: () -> Void
    let onRename: () -> Void
    let onReopen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.launcherBodyStrong)
                        .foregroundStyle(LauncherTheme.primaryText)
                        .lineLimit(1)

                    if item.isPinned {
                        LauncherChip(text: "置顶")
                    }

                    if let statusText = item.statusText {
                        LauncherChip(text: statusText)
                    }

                    Spacer(minLength: 8)
                }

                Text(formattedDateText(for: item.lastActivityAt))
                    .font(.launcherMeta)
                    .foregroundStyle(LauncherTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            menuButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white : LauncherTheme.softFill.opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? LauncherTheme.border.opacity(0.95) : LauncherTheme.border.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.06 : 0.02), radius: isSelected ? 10 : 4, x: 0, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if isMenuPresented {
                onDismissMenu()
            } else {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovering = hovering
            }
        }
    }

    private var menuButton: some View {
        GeometryReader { proxy in
            Button {
                onToggleMenu(proxy.frame(in: .named("SessionsWorkspace")))
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((isSelected || isMenuPresented) ? Color.white : LauncherTheme.softFill.opacity(0.42))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(LauncherTheme.border.opacity((isSelected || isMenuPresented) ? 0.9 : 0.35), lineWidth: 1)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(LauncherTheme.secondaryText.opacity((isSelected || isMenuPresented) ? 0.85 : 0.58))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }
                }
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(isSelected || isMenuPresented ? 0.05 : 0), radius: 4, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 28, height: 28)
    }

    private func formattedDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
