import FirebaseAuth
import Foundation

/// `AuthService` backed by Firebase Auth.
///
/// Firebase refreshes ID tokens on its own. This type makes that observable: the token listener
/// re-emits the session on every refresh, and when a refresh fails unrecoverably Firebase signs
/// the user out, which `SessionController` reports as an expired session.
struct FirebaseAuthService: AuthService {
    func sessionStates() -> AsyncStream<SessionState> {
        AsyncStream { continuation in
            let auth = Auth.auth()
            // `Auth` and `User` are not Sendable; only Sendable `SessionState` values leave the callbacks.
            let stateHandle = auth.addStateDidChangeListener { _, user in
                continuation.yield(Self.state(for: user))
            }
            let tokenHandle = auth.addIDTokenDidChangeListener { _, user in
                if user != nil { Log.auth.debug("ID token refreshed") }
                continuation.yield(Self.state(for: user))
            }
            // The handles are opaque tokens only ever passed back to Firebase's removal APIs,
            // which are thread-safe, so sending them to the termination handler is safe.
            nonisolated(unsafe) let handles = (stateHandle, tokenHandle)
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handles.0)
                Auth.auth().removeIDTokenDidChangeListener(handles.1)
            }
        }
    }

    func signIn(email: String, password: String) async throws(AuthError) -> AuthSession {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return Self.session(for: result.user)
        } catch {
            throw Self.map(error)
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws(AuthError) -> AuthSession {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
            return Self.session(for: result.user)
        } catch {
            throw Self.map(error)
        }
    }

    func sendPasswordReset(email: String) async throws(AuthError) {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw Self.map(error)
        }
    }

    func signOut() async throws(AuthError) {
        do {
            try Auth.auth().signOut()
        } catch {
            throw Self.map(error)
        }
    }

    func currentIDToken(forceRefresh: Bool) async throws(AuthError) -> String {
        guard let user = Auth.auth().currentUser else { throw .notSignedIn }
        do {
            return try await user.getIDToken(forcingRefresh: forceRefresh)
        } catch {
            throw Self.map(error)
        }
    }

    private static func state(for user: User?) -> SessionState {
        user.map { .signedIn(session(for: $0)) } ?? .signedOut(nil)
    }

    private static func session(for user: User) -> AuthSession {
        AuthSession(uid: user.uid, email: user.email ?? "", displayName: user.displayName)
    }

    /// Firebase codes the app distinguishes; everything else is `.unknown`.
    private static let errorsByCode: [AuthErrorCode: AuthError] = [
        .invalidEmail: .invalidEmail,
        // Firebase reports `invalidCredential` for both when email enumeration protection is on.
        .wrongPassword: .wrongCredentials,
        .userNotFound: .wrongCredentials,
        .invalidCredential: .wrongCredentials,
        .emailAlreadyInUse: .emailAlreadyInUse,
        .weakPassword: .weakPassword,
        .networkError: .network,
        .tooManyRequests: .tooManyRequests,
        .userTokenExpired: .userTokenExpired,
        .invalidUserToken: .invalidUserToken,
        .userDisabled: .userDisabled,
        .requiresRecentLogin: .requiresRecentLogin
    ]

    private static func map(_ error: any Error) -> AuthError {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: nsError.code) else {
            return .unknown
        }
        return errorsByCode[code] ?? .unknown
    }
}
