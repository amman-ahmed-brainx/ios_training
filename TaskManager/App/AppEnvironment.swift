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
            // Fakes never ship: Release builds always run live. Tests run the Debug configuration.
            if arguments.contains(uiTestArgument) { return .uiTest }
            // The unit-test bundle is hosted inside the app; keep it away from the real backend.
            if environment["XCTestConfigurationFilePath"] != nil { return .preview }
            #endif
            return .live
        }
    }

    /// Which backend this build talks to.
    enum BackendStatus: Equatable, Sendable {
        case firebase
        /// Live mode without `GoogleService-Info.plist`; sign-in is unavailable.
        case unconfigured
        case fake
    }

    let mode: Mode
    let clock: any AppClock
    let backendStatus: BackendStatus
    let auth: any AuthService
    let session: SessionController

    init(mode: Mode, clock: any AppClock = SystemClock()) {
        self.mode = mode
        self.clock = clock
        let backend = Self.makeBackend(for: mode)
        backendStatus = backend.status
        auth = backend.auth
        session = SessionController(auth: backend.auth, profiles: backend.profiles)
    }

    /// Creates the environment for the current process.
    static func make(arguments: [String], environment: [String: String]) -> AppEnvironment {
        AppEnvironment(mode: Mode.resolve(arguments: arguments, environment: environment))
    }

    #if DEBUG
    /// Environment used by `#Preview`s: fake backend, already signed in.
    static var preview: AppEnvironment {
        let environment = AppEnvironment(mode: .preview)
        environment.bootstrap()
        return environment
    }
    #endif

    /// Starts long-lived work (the session listener). Safe to call more than once.
    func bootstrap() {
        session.start()
    }

    // MARK: - View model factories

    func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(auth: auth)
    }

    func makeSignUpViewModel() -> SignUpViewModel {
        SignUpViewModel(auth: auth)
    }

    func makeForgotPasswordViewModel(email: String) -> ForgotPasswordViewModel {
        ForgotPasswordViewModel(auth: auth, email: email)
    }

    // MARK: - Backend selection

    private struct Backend {
        let status: BackendStatus
        let auth: any AuthService
        let profiles: any UserProfileStore
    }

    private static func makeBackend(for mode: Mode) -> Backend {
        #if DEBUG
        switch mode {
        case .preview:
            let fake = FakeAuthService(signedIn: true)
            return Backend(status: .fake, auth: fake, profiles: fake)
        case .uiTest:
            let fake = FakeAuthService()
            return Backend(status: .fake, auth: fake, profiles: fake)
        case .live:
            break
        }
        #endif
        if FirebaseBootstrap.configureIfAvailable() {
            return Backend(status: .firebase, auth: FirebaseAuthService(), profiles: FirestoreUserProfileStore())
        }
        Log.app.notice("GoogleService-Info.plist missing; running without a backend.")
        let unconfigured = UnconfiguredAuthService()
        return Backend(status: .unconfigured, auth: unconfigured, profiles: unconfigured)
    }
}
