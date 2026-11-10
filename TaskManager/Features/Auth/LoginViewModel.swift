import Foundation
import Observation

/// Email and password login. On success the session stream moves the app past the login screen.
@MainActor
@Observable
final class LoginViewModel {
    enum Field: Hashable, Sendable { case email, password }

    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    /// Server-side failure (wrong password, offline), shown above the form.
    private(set) var errorMessage: String?
    private var validation = InlineValidation<Field>()

    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    var emailError: String? { validation.message(for: .email, Validators.email(email)) }
    var passwordError: String? { validation.message(for: .password, Validators.required(password)) }

    private var isValid: Bool {
        Validators.email(email) == nil && Validators.required(password) == nil
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
            _ = try await auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
