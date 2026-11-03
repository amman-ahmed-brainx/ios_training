import Observation

/// Settings: account, sync and sign-out.
@MainActor
@Observable
final class SettingsViewModel {
    let session: AuthSession
    private(set) var isSigningOut = false
    private(set) var syncStatus = SyncStatus.idle
    private let sessionController: SessionController
    private let sync: (any SyncControlling)?

    init(session: AuthSession, sessionController: SessionController, sync: (any SyncControlling)? = nil) {
        self.session = session
        self.sessionController = sessionController
        self.sync = sync
    }

    var isSyncAvailable: Bool { sync != nil }

    func observeSync() async {
        guard let sync else { return }
        for await status in sync.statusUpdates() {
            syncStatus = status
        }
    }

    func syncNow() async {
        await sync?.syncNow()
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await sessionController.signOut()
    }
}
