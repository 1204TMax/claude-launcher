import SwiftUI
import FirebaseCore

@main
struct ClaudeLauncherApp: App {
    @StateObject private var appModel: AppModel

    init() {
        FirebaseApp.configure()
        let analyticsService = AnalyticsService(
            transport: FirebaseAnalyticsTransport(),
            identityDidChange: { installID in
                FirebaseAnalyticsTransport.configureIdentity(installID: installID)
            },
            collectionEnabledDidChange: { enabled in
                FirebaseAnalyticsTransport.setCollectionEnabled(enabled)
            }
        )
        _appModel = StateObject(wrappedValue: AppModel(analyticsService: analyticsService))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(appModel)
                .frame(minWidth: 520, minHeight: 620)
        }
    }
}
