/// Decides what to do when an authenticated operation fails with an auth error.
struct SessionExpiryPolicy: Sendable {
    enum Action: Equatable, Sendable {
        /// Transient: keep the session and try again later.
        case retry
        /// The session is fine but this action needs a fresh login.
        case reauthenticate
        /// The session is unusable: clear local state and return to login.
        case logout
    }

    /// - Parameter isSensitiveAction: `requiresRecentLogin` only matters for actions such as
    ///   account changes; for anything else it is treated as transient.
    func action(for error: AuthError, isSensitiveAction: Bool = false) -> Action {
        switch error {
        case .userTokenExpired, .invalidUserToken, .userDisabled, .notSignedIn:
            .logout
        case .requiresRecentLogin:
            isSensitiveAction ? .reauthenticate : .retry
        case .network, .tooManyRequests, .unknown:
            .retry
        case .invalidEmail, .wrongCredentials, .emailAlreadyInUse, .weakPassword, .notConfigured:
            // Input or configuration errors say nothing about the current session.
            .retry
        }
    }
}
