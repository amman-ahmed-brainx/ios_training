import Foundation

/// The signed-in user, as the rest of the app sees it. Independent of any backend SDK.
struct AuthSession: Equatable, Sendable {
    let uid: String
    let email: String
    let displayName: String?
}

/// Why the user ended up signed out; drives the message on the login screen.
enum SignOutReason: Equatable, Sendable {
    case userInitiated
    /// The backend no longer accepts the session (revoked, disabled, expired).
    case sessionExpired
    /// A sensitive action needs a fresh login.
    case reauthenticationRequired
}

/// Authentication state over time.
enum SessionState: Equatable, Sendable {
    /// Still resolving the persisted session at launch.
    case unknown
    case signedOut(SignOutReason?)
    case signedIn(AuthSession)
}

/// Authentication backend. Implemented by Firebase in production and by fakes in previews and tests.
protocol AuthService: Sendable {
    /// Emits the current state immediately, then every change (sign-in, sign-out, token refresh).
    func sessionStates() -> AsyncStream<SessionState>
    func signIn(email: String, password: String) async throws(AuthError) -> AuthSession
    func signUp(email: String, password: String, displayName: String) async throws(AuthError) -> AuthSession
    func sendPasswordReset(email: String) async throws(AuthError)
    func signOut() async throws(AuthError)
    /// A valid ID token for authenticating REST calls (the background uploader).
    /// Pass `forceRefresh: true` to bypass the SDK's cached token.
    func currentIDToken(forceRefresh: Bool) async throws(AuthError) -> String
}
