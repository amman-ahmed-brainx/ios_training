import Testing
@testable import TaskManager

struct SessionExpiryPolicyTests {
    private let policy = SessionExpiryPolicy()

    @Test(arguments: [AuthError.userTokenExpired, .invalidUserToken, .userDisabled, .notSignedIn])
    func unrecoverableErrorsLogOut(_ error: AuthError) {
        #expect(policy.action(for: error) == .logout)
        #expect(policy.action(for: error, isSensitiveAction: true) == .logout)
    }

    @Test(arguments: [AuthError.network, .tooManyRequests, .unknown])
    func transientErrorsRetry(_ error: AuthError) {
        #expect(policy.action(for: error) == .retry)
    }

    @Test func recentLoginOnSensitiveActionReauthenticates() {
        #expect(policy.action(for: .requiresRecentLogin, isSensitiveAction: true) == .reauthenticate)
    }

    @Test func recentLoginOnRoutineActionDoesNotEndTheSession() {
        #expect(policy.action(for: .requiresRecentLogin) == .retry)
    }

    @Test(arguments: [AuthError.invalidEmail, .wrongCredentials, .emailAlreadyInUse, .weakPassword])
    func inputErrorsNeverEndTheSession(_ error: AuthError) {
        #expect(policy.action(for: error) == .retry)
    }
}
