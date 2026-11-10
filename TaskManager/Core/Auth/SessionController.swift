import Foundation
import Observation

/// Owns the app's session state: follows the auth stream, ends sessions cleanly, and applies
/// `SessionExpiryPolicy` when an authenticated operation fails.
@MainActor
@Observable
final class SessionController {
    private(set) var state: SessionState = .unknown

    var currentSession: AuthSession? {
        if case .signedIn(let session) = state { session } else { nil }
    }

    private let auth: any AuthService
    private let profiles: any UserProfileStore
    private let policy: SessionExpiryPolicy
    private var observers: [any SessionLifecycleObserver] = []
    private var listenTask: Task<Void, Never>?
    private var profileTask: Task<Void, Never>?

    init(auth: any AuthService, profiles: any UserProfileStore, policy: SessionExpiryPolicy = SessionExpiryPolicy()) {
        self.auth = auth
        self.profiles = profiles
        self.policy = policy
    }

    /// Adds a component that must release per-user state when the session ends.
    func register(_ observer: any SessionLifecycleObserver) {
        observers.append(observer)
    }

    /// Starts following the auth backend. Safe to call more than once.
    func start() {
        guard listenTask == nil else { return }
        let states = auth.sessionStates()
        listenTask = Task { [weak self] in
            for await next in states {
                guard let self else { return }
                await self.apply(next)
            }
        }
    }

    /// Stops following the auth backend and cancels in-flight profile work.
    func stop() {
        listenTask?.cancel()
        listenTask = nil
        profileTask?.cancel()
        profileTask = nil
    }

    /// User-initiated sign-out. Cleanup runs first, while the user is still authenticated,
    /// so observers can remove remote state such as this device's push token.
    func signOut() async {
        guard let session = currentSession else { return }
        await endSession(session, reason: .userInitiated)
        do {
            try await auth.signOut()
        } catch {
            // Local state is already cleared; the SDK will drop the session on next launch.
            Log.auth.error("Sign-out failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies the expiry policy to a failed authenticated operation.
    /// - Returns: the action taken, so callers know whether to retry.
    @discardableResult
    func handle(_ error: AuthError, isSensitiveAction: Bool = false) async -> SessionExpiryPolicy.Action {
        let action = policy.action(for: error, isSensitiveAction: isSensitiveAction)
        guard let session = currentSession else { return action }
        switch action {
        case .retry:
            break
        case .reauthenticate:
            await forceSignOut(session, reason: .reauthenticationRequired)
        case .logout:
            Log.auth.notice("Session ended by policy after \(String(describing: error), privacy: .public)")
            await forceSignOut(session, reason: .sessionExpired)
        }
        return action
    }

    /// Asks the backend for a valid token (refreshing it if needed) and logs out if that fails
    /// unrecoverably. Called when the app becomes active.
    func validateSession() async {
        guard currentSession != nil else { return }
        do {
            _ = try await auth.currentIDToken(forceRefresh: false)
        } catch {
            await handle(error)
        }
    }

    private func apply(_ next: SessionState) async {
        switch next {
        case .unknown:
            break
        case .signedIn(let session):
            let isNewSession = currentSession?.uid != session.uid
            state = .signedIn(session)
            if isNewSession {
                ensureProfile(for: session)
                for observer in observers {
                    await observer.sessionDidStart(session)
                }
            }
        case .signedOut(let reason):
            if let session = currentSession {
                // We did not ask for this: the backend dropped the session (revoked or disabled).
                await endSession(session, reason: reason ?? .sessionExpired)
            } else if state == .unknown {
                state = .signedOut(reason)
            }
            // Already signed out: keep the reason we recorded when we ended the session.
        }
    }

    private func forceSignOut(_ session: AuthSession, reason: SignOutReason) async {
        await endSession(session, reason: reason)
        // Clear the SDK's persisted user too; failures are irrelevant once local state is gone.
        try? await auth.signOut()
    }

    private func endSession(_ session: AuthSession, reason: SignOutReason) async {
        // Flip the UI first so nothing keeps using the session while cleanup runs.
        state = .signedOut(reason)
        profileTask?.cancel()
        profileTask = nil
        for observer in observers {
            await observer.sessionWillEnd(uid: session.uid, reason: reason)
        }
    }

    private func ensureProfile(for session: AuthSession) {
        profileTask?.cancel()
        // Not awaited inline: an offline Firestore write only completes on reconnect and must not
        // hold up the session stream. Retried on every sign-in and launch.
        profileTask = Task { [profiles] in
            do {
                try await profiles.ensureProfile(for: session)
            } catch is CancellationError {
                return
            } catch {
                Log.auth.error("Could not save user profile: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
