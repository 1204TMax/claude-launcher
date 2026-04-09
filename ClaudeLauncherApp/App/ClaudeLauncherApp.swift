import SwiftUI

@main
struct ClaudeLauncherApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建配置") {
                    appModel.createProfile()
                }
                .keyboardShortcut("n")
            }
        }
    }
}
