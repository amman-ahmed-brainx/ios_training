/// Used in live mode when `GoogleService-Info.plist` is missing: always signed out, every call fails
/// with `.notConfigured`, so the login screen can explain why instead of crashing.
struct UnconfiguredAuthService: AuthService, UserProfileStore {
    func sessionStates() -> AsyncStream<SessionState> {
        AsyncStream { continuation in
            continuation.yield(.signedOut(nil))
            continuation.finish()
        }
    }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthSession { throw .notConfigured }

    func signUp(email: String, password: String, displayName: String) async throws(AuthError) -> AuthSession {
        throw .notConfigured
    }

    func sendPasswordReset(email: String) async throws(AuthError) { throw .notConfigured }

    func signOut() async throws(AuthError) {}

    func currentIDToken(forceRefresh: Bool) async throws(AuthError) -> String { throw .notSignedIn }

    func ensureProfile(for session: AuthSession) async throws {}
}
