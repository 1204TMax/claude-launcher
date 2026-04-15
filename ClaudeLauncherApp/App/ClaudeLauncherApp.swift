import SwiftUI

@main
struct ClaudeLauncherApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(appModel)
                .frame(minWidth: 520, minHeight: 620)
        }
    }
}
