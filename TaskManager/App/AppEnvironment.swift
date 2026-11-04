import Foundation
import Observation
import SwiftData
import UIKit

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
    /// `nil` without a backend; attachments are then hidden.
    let attachmentStorage: (any AttachmentStorage)?
    let imageCompressor = ImageCompressor()
    let router: AppRouter
    /// `nil` without a backend; sharing is then hidden.
    let directory: (any UserDirectory)?
    let reminders: ReminderScheduler
    let reminderCoordinator: ReminderCoordinator
    /// `nil` unless Firebase is configured.
    let push: (any PushRegistering)?
    let notificationCoordinator: NotificationCoordinator
    /// Background uploads for large attachments; `nil` without Firebase Storage.
    let uploads: BackgroundUploadManager?
    let backgroundSessionEvents = BackgroundSessionEvents()

    init(mode: Mode, clock: any AppClock = SystemClock()) {
        self.mode = mode
        self.clock = clock
        let backend = Self.makeBackend(for: mode)
        backendStatus = backend.status
        auth = backend.auth
        session = SessionController(auth: backend.auth, profiles: backend.profiles)
        // Fakes get a fresh in-memory store each launch so previews and UI tests are deterministic.
        let container = Self.makeContainer(inMemory: mode != .live)
        let local = container.map { LocalTaskRepository(container: $0, clock: clock) }
        tasks = local ?? UnavailableTaskRepository()
        attachmentStorage = backend.storage
        if let local, let remote = backend.remote {
            let engine = SyncEngine(remote: remote, repository: local, storage: backend.storage, clock: clock)
            sync = engine
            session.register(engine)
        } else {
            sync = nil
        }
        router = AppRouter()
        notificationCoordinator = NotificationCoordinator(router: router)
        directory = backend.directory
        reminders = ReminderScheduler(clock: clock)
        reminderCoordinator = ReminderCoordinator(scheduler: reminders, repository: tasks)
        session.register(reminderCoordinator)
        if backend.status == .firebase {
            let registrar = FirebasePushRegistrar()
            push = registrar
            session.register(registrar)
        } else {
            push = nil
        }
        if backend.status == .firebase, let container, let bucket = BackgroundUploadManager.configuredBucket {
            let manager = BackgroundUploadManager(
                container: ModelContainerHandle(container: container),
                auth: backend.auth,
                repository: tasks,
                bucket: bucket,
                sessionEvents: backgroundSessionEvents
            )
            uploads = manager
            session.register(manager)
        } else {
            uploads = nil
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
        if let uploads {
            Task { await uploads.activate() }
        }
    }

    // MARK: - App lifecycle

    /// Leaving the foreground: get a little time to flush pending changes, and line up background sync.
    func didEnterBackground() {
        BackgroundSync.schedule()
        guard let sync else { return }
        let token = BackgroundTaskToken()
        token.begin(name: "Flush pending changes")
        Task {
            await sync.pushPendingChanges()
            token.end()
        }
    }

    /// Back in the foreground: re-check the session, sync, and reconcile reminders.
    func didBecomeActive() {
        Task {
            await session.validateSession()
            await sync?.syncNow()
            await reminderCoordinator.refresh()
        }
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
        TaskListViewModel(repository: tasks, userId: session.uid, clock: clock, sync: sync, reminders: reminderCoordinator)
    }

    func makeTaskDetailViewModel(taskId: String, session: AuthSession) -> TaskDetailViewModel {
        TaskDetailViewModel(taskId: taskId, repository: tasks, userId: session.uid, clock: clock)
    }

    func makeTaskEditorViewModel(editing task: TaskItem?, session: AuthSession) -> TaskEditorViewModel {
        TaskEditorViewModel(editing: task, repository: tasks, userId: session.uid, clock: clock)
    }

    func makeAttachmentsViewModel(taskId: String, session: AuthSession) -> AttachmentsViewModel? {
        guard let attachmentStorage else { return nil }
        return AttachmentsViewModel(
            taskId: taskId,
            userId: session.uid,
            repository: tasks,
            storage: attachmentStorage,
            compressor: imageCompressor,
            uploader: uploads
        )
    }

    func makeInviteViewModel(task: TaskItem, session: AuthSession) -> InviteCollaboratorViewModel? {
        guard let directory else { return nil }
        return InviteCollaboratorViewModel(task: task, userId: session.uid, repository: tasks, directory: directory)
    }

    func makeSettingsViewModel(session: AuthSession) -> SettingsViewModel {
        SettingsViewModel(
            session: session,
            sessionController: self.session,
            sync: sync,
            reminderCoordinator: reminderCoordinator,
            repository: tasks
        )
    }

    // MARK: - Backend selection

    private static func makeContainer(inMemory: Bool) -> ModelContainer? {
        do {
            return try PersistenceContainer.make(inMemory: inMemory)
        } catch {
            Log.app.fault("Opening the task store failed: \(error.localizedDescription, privacy: .public)")
        }
        // A broken on-disk store must not stop the app: keep working in memory for this launch.
        do {
            return try PersistenceContainer.make(inMemory: true)
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
        let storage: (any AttachmentStorage)?
        let directory: (any UserDirectory)?
    }

    #if DEBUG
    private static func fakeBackend(auth: FakeAuthService) -> Backend {
        Backend(status: .fake, auth: auth, profiles: auth, remote: FakeTaskRemote(),
                storage: FakeAttachmentStorage(), directory: FakeUserDirectory())
    }
    #endif

    private static func makeBackend(for mode: Mode) -> Backend {
        #if DEBUG
        switch mode {
        case .preview:
            let fake = FakeAuthService(signedIn: true)
            return Self.fakeBackend(auth: fake)
        case .uiTest:
            let fake = FakeAuthService()
            return Self.fakeBackend(auth: fake)
        case .live:
            break
        }
        #endif
        if FirebaseBootstrap.configureIfAvailable() {
            return Backend(
                status: .firebase,
                auth: FirebaseAuthService(),
                profiles: FirestoreUserProfileStore(),
                remote: FirestoreTaskRemote(),
                storage: FirebaseAttachmentStorage(),
                directory: FirestoreUserDirectory()
            )
        }
        Log.app.notice("GoogleService-Info.plist missing; running without a backend.")
        let unconfigured = UnconfiguredAuthService()
        return Backend(status: .unconfigured, auth: unconfigured, profiles: unconfigured, remote: nil, storage: nil, directory: nil)
    }
}

/// A `beginBackgroundTask` assertion that is always ended exactly once.
@MainActor
final class BackgroundTaskToken {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
