import Foundation
import Observation

/// Account creation with name, email, password and confirmation.
@MainActor
@Observable
final class SignUpViewModel {
    enum Field: Hashable, Sendable { case name, email, password, confirmPassword }

    var displayName = ""
    var email = ""
    var password = ""
    var confirmPassword = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private var validation = InlineValidation<Field>()

    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    var nameError: String? { validation.message(for: .name, Validators.required(displayName)) }
    var emailError: String? { validation.message(for: .email, Validators.email(email)) }
    var passwordError: String? { validation.message(for: .password, Validators.newPassword(password)) }
    var confirmPasswordError: String? {
        validation.message(for: .confirmPassword, Validators.confirmation(confirmPassword, matches: password))
    }

    private var isValid: Bool {
        Validators.required(displayName) == nil
            && Validators.email(email) == nil
            && Validators.newPassword(password) == nil
            && Validators.confirmation(confirmPassword, matches: password) == nil
    }

    func didEndEditing(_ field: Field) {
        validation.didEndEditing(field)
    }

    func submit() async {
        guard !isSubmitting else { return }
        validation.didAttemptSubmit()
        errorMessage = nil
        guard isValid else { return }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await auth.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
