#if DEBUG
import Foundation

/// In-memory auth backend for previews and `-uitest` runs. Never compiled into Release.
actor FakeAuthService: AuthService, UserProfileStore {
    /// Account the UI test signs in with.
    static let uiTestEmail = "test@example.com"
    static let uiTestPassword = "Password1"

    private struct Account {
        let password: String
        let session: AuthSession
    }

    private var accounts: [String: Account] = [:]
    private var current: AuthSession?
    private var subscribers: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    /// - Parameter signedIn: start with the seeded account already signed in (handy for previews).
    init(signedIn: Bool = false) {
        let session = AuthSession(uid: "uitest-user", email: Self.uiTestEmail, displayName: "Test User")
        accounts[Self.uiTestEmail] = Account(password: Self.uiTestPassword, session: session)
        current = signedIn ? session : nil
    }

    nonisolated func sessionStates() -> AsyncStream<SessionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionState.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        Task { await self.subscribe(continuation, id: id) }
        return stream
    }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthSession {
        guard let account = accounts[email.lowercased()], account.password == password else {
            throw .wrongCredentials
        }
        setCurrent(account.session)
        return account.session
    }

    func signUp(email: String, password: String, displayName: String) async throws(AuthError) -> AuthSession {
        let key = email.lowercased()
        guard accounts[key] == nil else { throw .emailAlreadyInUse }
        let session = AuthSession(uid: UUID().uuidString, email: key, displayName: displayName)
        accounts[key] = Account(password: password, session: session)
        setCurrent(session)
        return session
    }

    func sendPasswordReset(email: String) async throws(AuthError) {}

    func signOut() async throws(AuthError) {
        setCurrent(nil)
    }

    func currentIDToken(forceRefresh: Bool) async throws(AuthError) -> String {
        guard let current else { throw .notSignedIn }
        return "fake-token-\(current.uid)"
    }

    func ensureProfile(for session: AuthSession) async throws {}

    private func subscribe(_ continuation: AsyncStream<SessionState>.Continuation, id: UUID) {
        subscribers[id] = continuation
        continuation.yield(current.map { .signedIn($0) } ?? .signedOut(nil))
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func setCurrent(_ session: AuthSession?) {
        current = session
        let state: SessionState = session.map { .signedIn($0) } ?? .signedOut(nil)
        for continuation in subscribers.values {
            continuation.yield(state)
        }
    }
}
#endif
