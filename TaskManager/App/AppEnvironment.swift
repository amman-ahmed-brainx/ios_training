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
    let tasks: any TaskRepository
    /// `nil` when there is no backend (no Firebase plist) or no local store.
    let sync: SyncEngine?
    let router = AppRouter()

    init(mode: Mode, clock: any AppClock = SystemClock()) {
        self.mode = mode
        self.clock = clock
        let backend = Self.makeBackend(for: mode)
        backendStatus = backend.status
        auth = backend.auth
        session = SessionController(auth: backend.auth, profiles: backend.profiles)
        // Fakes get a fresh in-memory store each launch so previews and UI tests are deterministic.
        let local = Self.makeLocalRepository(inMemory: mode != .live, clock: clock)
        tasks = local ?? UnavailableTaskRepository()
        if let local, let remote = backend.remote {
            let engine = SyncEngine(remote: remote, repository: local, clock: clock)
            sync = engine
            session.register(engine)
        } else {
            sync = nil
        }
        // Registered last: the cache is wiped only after sync has stopped (and flushed).
        session.register(TaskCacheCleaner(repository: tasks))
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

    func makeTaskListViewModel(session: AuthSession) -> TaskListViewModel {
        TaskListViewModel(repository: tasks, userId: session.uid, clock: clock, sync: sync)
    }

    func makeTaskDetailViewModel(taskId: String, session: AuthSession) -> TaskDetailViewModel {
        TaskDetailViewModel(taskId: taskId, repository: tasks, userId: session.uid, clock: clock)
    }

    func makeTaskEditorViewModel(editing task: TaskItem?, session: AuthSession) -> TaskEditorViewModel {
        TaskEditorViewModel(editing: task, repository: tasks, userId: session.uid, clock: clock)
    }

    func makeSettingsViewModel(session: AuthSession) -> SettingsViewModel {
        SettingsViewModel(session: session, sessionController: self.session, sync: sync)
    }

    // MARK: - Backend selection

    private static func makeLocalRepository(inMemory: Bool, clock: any AppClock) -> LocalTaskRepository? {
        do {
            return LocalTaskRepository(container: try PersistenceContainer.make(inMemory: inMemory), clock: clock)
        } catch {
            Log.app.fault("Opening the task store failed: \(error.localizedDescription, privacy: .public)")
        }
        // A broken on-disk store must not stop the app: keep working in memory for this launch.
        do {
            return LocalTaskRepository(container: try PersistenceContainer.make(inMemory: true), clock: clock)
        } catch {
            Log.app.fault("Opening an in-memory task store failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private struct Backend {
        let status: BackendStatus
        let auth: any AuthService
        let profiles: any UserProfileStore
        let remote: (any TaskRemote)?
    }

    private static func makeBackend(for mode: Mode) -> Backend {
        #if DEBUG
        switch mode {
        case .preview:
            let fake = FakeAuthService(signedIn: true)
            return Backend(status: .fake, auth: fake, profiles: fake, remote: FakeTaskRemote())
        case .uiTest:
            let fake = FakeAuthService()
            return Backend(status: .fake, auth: fake, profiles: fake, remote: FakeTaskRemote())
        case .live:
            break
        }
        #endif
        if FirebaseBootstrap.configureIfAvailable() {
            return Backend(
                status: .firebase,
                auth: FirebaseAuthService(),
                profiles: FirestoreUserProfileStore(),
                remote: FirestoreTaskRemote()
            )
        }
        Log.app.notice("GoogleService-Info.plist missing; running without a backend.")
        let unconfigured = UnconfiguredAuthService()
        return Backend(status: .unconfigured, auth: unconfigured, profiles: unconfigured, remote: nil)
    }
}
