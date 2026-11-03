import Foundation
import Observation

/// Sends a password reset email.
@MainActor
@Observable
final class ForgotPasswordViewModel {
    enum Status: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    var email: String
    private(set) var status: Status = .idle
    private var validation = InlineValidation<Field>()

    private enum Field: Hashable, Sendable { case email }

    private let auth: any AuthService

    /// - Parameter email: prefilled from the login form so the user doesn't retype it.
    init(auth: any AuthService, email: String = "") {
        self.auth = auth
        self.email = email
    }

    var emailError: String? { validation.message(for: .email, Validators.email(email)) }

    func didEndEditingEmail() {
        validation.didEndEditing(.email)
    }

    func submit() async {
        guard status != .sending else { return }
        validation.didAttemptSubmit()
        guard Validators.email(email) == nil else { return }

        status = .sending
        do {
            try await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            status = .sent
        } catch .wrongCredentials {
            // "No such user" must look exactly like success, or this screen reveals which emails
            // have accounts. It would also show a password error on a screen without a password.
            status = .sent
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
