import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedSection: AppSection = .launch

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                LauncherTheme.appBackground.ignoresSafeArea()
                Group {
                    switch selectedSection {
                    case .launch:
                        LaunchWorkspaceView()
                    case .sessions:
                        SessionsWorkspaceView()
                    }
                }
            }
        }
        .background(LauncherTheme.appBackground)
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

    private var topBar: some View {
        HStack {
            Spacer()

            LauncherSegmentedControl(
                items: AppSection.allCases.map { ($0, $0.title) },
                selection: $selectedSection
            )

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(LauncherTheme.appBackground.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LauncherTheme.border.opacity(0.7))
                .frame(height: 1)
        }
    }
}
