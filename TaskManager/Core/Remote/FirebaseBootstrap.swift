import FirebaseCore
import Foundation

/// The only place `FirebaseApp` is configured.
enum FirebaseBootstrap {
    /// Configures Firebase if `GoogleService-Info.plist` is bundled.
    /// - Returns: `false` when the plist is missing, so the app can still run offline.
    static func configureIfAvailable(bundle: Bundle = .main) -> Bool {
        if FirebaseApp.app() != nil { return true }
        guard
            let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
            let options = FirebaseOptions(contentsOfFile: path)
        else { return false }
        FirebaseApp.configure(options: options)
        return true
    }
}
