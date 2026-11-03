import UIKit
import UserNotifications

/// Receives the UIKit-only callbacks SwiftUI does not expose and owns the dependency graph.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let environment: AppEnvironment

    override init() {
        environment = AppEnvironment.make(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        environment.bootstrap()
        UNUserNotificationCenter.current().delegate = environment.notificationCoordinator
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        environment.push?.setAPNsToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Log.notifications.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}
