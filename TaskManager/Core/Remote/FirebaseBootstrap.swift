import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// The only place `FirebaseApp` is configured.
enum FirebaseBootstrap {
    /// Debug-only launch argument that points Auth, Firestore and Storage at the Local Emulator Suite
    /// (`firebase emulators:start --only auth,firestore,storage`), so the full Firebase code path can
    /// be exercised without touching the production project.
    static let emulatorArgument = "-firebaseEmulators"
    static let emulatorHost = "127.0.0.1"

    /// Whether this process talks to the local emulators instead of production.
    static var usesEmulators: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(emulatorArgument)
        #else
        false
        #endif
    }

    /// Configures Firebase if `GoogleService-Info.plist` is bundled.
    /// - Returns: `false` when the plist is missing, so the app can still run offline.
    static func configureIfAvailable(bundle: Bundle = .main) -> Bool {
        // `FirebaseApp.app()` logs an error when nothing is configured yet; `allApps` doesn't.
        if FirebaseApp.allApps?.isEmpty == false { return true }
        guard
            let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
            let options = FirebaseOptions(contentsOfFile: path)
        else { return false }
        FirebaseApp.configure(options: options)
        // Deliver snapshot callbacks on a background queue so parsing never runs on main.
        let settings = Firestore.firestore().settings
        settings.dispatchQueue = DispatchQueue(label: "com.brainxtech.taskmanager.firestore", qos: .userInitiated)
        if usesEmulators {
            settings.host = "\(emulatorHost):8080"
            settings.isSSLEnabled = false
            Auth.auth().useEmulator(withHost: emulatorHost, port: 9099)
            Storage.storage().useEmulator(withHost: emulatorHost, port: 9199)
            Log.app.notice("Using the Firebase Local Emulator Suite")
        }
        Firestore.firestore().settings = settings
        return true
    }
}
