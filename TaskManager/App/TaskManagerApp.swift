import SwiftUI

@main
struct TaskManagerApp: App {
    // The delegate owns the environment because UIKit callbacks (APNs, background URLSession)
    // can arrive before or without any SwiftUI scene.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(environment: appDelegate.environment)
        }
    }
}
