import FirebaseCore
import FirebaseFirestore
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
        // Deliver snapshot callbacks on a background queue so parsing never runs on main.
        let settings = Firestore.firestore().settings
        settings.dispatchQueue = DispatchQueue(label: "com.brainxtech.taskmanager.firestore", qos: .userInitiated)
        Firestore.firestore().settings = settings
        return true
    }
}
