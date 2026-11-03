import UIKit

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
        return true
    }
}
