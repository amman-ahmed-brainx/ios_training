@testable import TaskManager

extension AuthSession {
    static let ada = AuthSession(uid: "uid-ada", email: "ada@example.com", displayName: "Ada")
    static let grace = AuthSession(uid: "uid-grace", email: "grace@example.com", displayName: "Grace")
}

/// Records every call and returns scripted results. Drive the session stream with `emit(_:)`.
actor MockAuthService: AuthService {
    struct SignUpCall: Equatable { let email, password, displayName: String }
    struct SignInCall: Equatable { let email, password: String }

    private nonisolated let stream: AsyncStream<SessionState>
    private nonisolated let continuation: AsyncStream<SessionState>.Continuation

    private(set) var signInCalls: [SignInCall] = []
    private(set) var signUpCalls: [SignUpCall] = []
    private(set) var resetCalls: [String] = []
    private(set) var signOutCount = 0
    private(set) var tokenRequests: [Bool] = []

    private var signInResult: Result<AuthSession, AuthError> = .success(.ada)
    private var signUpResult: Result<AuthSession, AuthError> = .success(.ada)
    private var resetError: AuthError?
    private var tokenResult: Result<String, AuthError> = .success("token")

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: SessionState.self)
    }

    nonisolated func emit(_ state: SessionState) {
        continuation.yield(state)
    }

    func failSignIn(with error: AuthError) { signInResult = .failure(error) }
    func failSignUp(with error: AuthError) { signUpResult = .failure(error) }
    func failReset(with error: AuthError) { resetError = error }
    func failToken(with error: AuthError) { tokenResult = .failure(error) }

    nonisolated func sessionStates() -> AsyncStream<SessionState> { stream }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthSession {
        signInCalls.append(SignInCall(email: email, password: password))
        return try signInResult.get()
    }

    func signUp(email: String, password: String, displayName: String) async throws(AuthError) -> AuthSession {
        signUpCalls.append(SignUpCall(email: email, password: password, displayName: displayName))
        return try signUpResult.get()
    }

    func sendPasswordReset(email: String) async throws(AuthError) {
        resetCalls.append(email)
        if let resetError { throw resetError }
    }

    func signOut() async throws(AuthError) {
        signOutCount += 1
        // Like Firebase, signing out re-emits the (now signed-out) state.
        continuation.yield(.signedOut(nil))
    }

    func currentIDToken(forceRefresh: Bool) async throws(AuthError) -> String {
        tokenRequests.append(forceRefresh)
        return try tokenResult.get()
    }
}

actor MockUserProfileStore: UserProfileStore {
    private(set) var ensuredSessions: [AuthSession] = []
    private var error: (any Error)?

    func fail(with error: any Error) { self.error = error }

    func ensureProfile(for session: AuthSession) async throws {
        ensuredSessions.append(session)
        if let error { throw error }
    }
}

/// Records session-end notifications and how many sign-outs had happened at that moment,
/// so tests can assert cleanup runs before the backend sign-out.
actor MockSessionObserver: SessionLifecycleObserver {
    struct Event: Equatable {
        let uid: String
        let reason: SignOutReason
        let signOutsBefore: Int
    }

    private let auth: MockAuthService
    private(set) var events: [Event] = []

    init(auth: MockAuthService) {
        self.auth = auth
    }

    func sessionWillEnd(uid: String, reason: SignOutReason) async {
        events.append(Event(uid: uid, reason: reason, signOutsBefore: await auth.signOutCount))
    }
}
