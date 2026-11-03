import Observation

/// Account section of Settings. Sync, reminder and export settings join it in later phases.
@MainActor
@Observable
final class SettingsViewModel {
    let session: AuthSession
    private(set) var isSigningOut = false
    private let sessionController: SessionController

    init(session: AuthSession, sessionController: SessionController) {
        self.session = session
        self.sessionController = sessionController
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await sessionController.signOut()
    }
}
