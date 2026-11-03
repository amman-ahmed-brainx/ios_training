import SwiftUI

/// Sheet that sends a password reset email.
struct ForgotPasswordView: View {
    @State private var model: ForgotPasswordViewModel
    @FocusState private var isEmailFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: ForgotPasswordViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    AuthHeader(
                        title: "Reset Password",
                        subtitle: "We'll email you a link to choose a new password."
                    )

                    switch model.status {
                    case .sent:
                        MessageBanner(
                            String(localized: "If an account exists for \(model.email), a reset link is on its way."),
                            kind: .info
                        )
                        .accessibilityIdentifier("forgotPassword.sent")
                    case .failed(let message):
                        MessageBanner(message, kind: .error)
                    case .idle, .sending:
                        EmptyView()
                    }

                    FormField("Email", text: $model.email, kind: .email, error: model.emailError, identifier: "forgotPassword.email")
                        .focused($isEmailFocused)
                        .submitLabel(.send)
                        .onSubmit(submit)

                    PrimaryButton("Send Reset Link", isLoading: model.status == .sending, action: submit)
                        .accessibilityIdentifier("forgotPassword.submit")
                }
                .padding(Spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Forgot Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: isEmailFocused) { wasFocused, _ in
                if wasFocused { model.didEndEditingEmail() }
            }
        }
    }

    private func submit() {
        isEmailFocused = false
        Task { await model.submit() }
    }
}

#if DEBUG
#Preview {
    ForgotPasswordView(model: ForgotPasswordViewModel(auth: FakeAuthService(), email: "test@example.com"))
}
#endif
