import Foundation
import Observation

/// Builds and owns the app's dependency graph. View models receive protocols from here
/// through their initialisers; nothing reaches for a singleton.
@MainActor
@Observable
final class AppEnvironment {
    /// Which set of implementations the graph is built from.
    enum Mode: Equatable, Sendable {
        /// Real backend (Firebase when configured).
        case live
        /// In-memory fakes for SwiftUI previews and the unit-test host.
        case preview
        /// Deterministic offline fakes driven by XCUITest via `-uitest`.
        case uiTest

        static let uiTestArgument = "-uitest"

        /// Picks the mode from launch arguments and the process environment.
        static func resolve(arguments: [String], environment: [String: String]) -> Mode {
            #if DEBUG
            // Fakes never ship: Release builds ignore the flag. UI tests run the Debug configuration.
            if arguments.contains(uiTestArgument) { return .uiTest }
            #endif
            // The unit-test bundle is hosted inside the app; keep it away from the real backend.
            if environment["XCTestConfigurationFilePath"] != nil { return .preview }
            return .live
        }
    }

    /// Whether a real backend is reachable from this build.
    enum BackendStatus: Equatable, Sendable {
        case notStarted
        case firebase
        /// Live mode without `GoogleService-Info.plist`; the app runs on local data only.
        case unconfigured
        case fake
    }

    let mode: Mode
    let clock: any AppClock
    private(set) var backendStatus: BackendStatus = .notStarted

    init(mode: Mode, clock: any AppClock = SystemClock()) {
        self.mode = mode
        self.clock = clock
    }

    /// Creates the environment for the current process.
    static func make(arguments: [String], environment: [String: String]) -> AppEnvironment {
        AppEnvironment(mode: Mode.resolve(arguments: arguments, environment: environment))
    }

    /// Environment used by `#Preview`s.
    static var preview: AppEnvironment {
        let environment = AppEnvironment(mode: .preview)
        environment.bootstrap()
        return environment
    }

    /// Starts SDKs that must be configured once at launch. Safe to call more than once.
    func bootstrap() {
        guard backendStatus == .notStarted else { return }
        switch mode {
        case .live:
            backendStatus = FirebaseBootstrap.configureIfAvailable() ? .firebase : .unconfigured
            if backendStatus == .unconfigured {
                Log.app.notice("GoogleService-Info.plist missing; running without a backend.")
            }
        case .preview, .uiTest:
            backendStatus = .fake
        }
    }
}
