import SwiftUI
import UserNotifications

@main
struct UpslopeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active: Task { await model.refresh() }
            case .background: Refresher.scheduleBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Refresher.taskID)) {
            Refresher.scheduleBackground()
            await Refresher.shared.run(reason: .background)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Created at launch so significant-location relaunches reach the delegate.
        LocationService.shared.startMonitoringIfAllowed()
        return true
    }

    /// Show alerts while the app is open too, still without sound.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
