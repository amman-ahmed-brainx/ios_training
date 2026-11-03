import SwiftUI

/// New account form.
struct SignUpView: View {
    @State private var model: SignUpViewModel
    @FocusState private var focus: SignUpViewModel.Field?

    init(model: SignUpViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AuthHeader(title: "Create Account", subtitle: "Plan, share and finish tasks together.")

                if let error = model.errorMessage {
                    MessageBanner(error, kind: .error)
                        .accessibilityIdentifier("signUp.error")
                }

                VStack(spacing: Spacing.large) {
                    FormField("Name", text: $model.displayName, kind: .name, error: model.nameError, identifier: "signUp.name")
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }

                    FormField("Email", text: $model.email, kind: .email, error: model.emailError, identifier: "signUp.email")
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        FormField(
                            "Password",
                            text: $model.password,
                            kind: .newPassword,
                            error: model.passwordError,
                            identifier: "signUp.password"
                        )
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .confirmPassword }
                        if model.passwordError == nil {
                            Text("At least 8 characters, with a letter and a number.")
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }

                    FormField(
                        "Confirm Password",
                        text: $model.confirmPassword,
                        kind: .newPassword,
                        error: model.confirmPasswordError,
                        identifier: "signUp.confirmPassword"
                    )
                    .focused($focus, equals: .confirmPassword)
                    .submitLabel(.join)
                    .onSubmit(submit)
                }

                PrimaryButton("Create Account", isLoading: model.isSubmitting, action: submit)
                    .accessibilityIdentifier("signUp.submit")
            }
            .padding(Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focus) { previous, _ in
            if let previous { model.didEndEditing(previous) }
        }
    }

    private func submit() {
        focus = nil
        Task { await model.submit() }
    }
}

#if DEBUG
#Preview("Empty") {
    NavigationStack { SignUpView(model: SignUpViewModel(auth: FakeAuthService())) }
}

#Preview("Dark, AX5") {
    NavigationStack { SignUpView(model: SignUpViewModel(auth: FakeAuthService())) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
#endif
