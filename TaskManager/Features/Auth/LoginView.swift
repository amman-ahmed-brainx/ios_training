import SwiftUI

/// Email/password login with links to sign-up and password reset.
struct LoginView: View {
    @State private var model: LoginViewModel
    @FocusState private var focus: LoginViewModel.Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let signOutReason: SignOutReason?
    private let onSignUp: () -> Void
    private let onForgotPassword: (String) -> Void

    init(
        model: LoginViewModel,
        signOutReason: SignOutReason?,
        onSignUp: @escaping () -> Void,
        onForgotPassword: @escaping (String) -> Void
    ) {
        _model = State(initialValue: model)
        self.signOutReason = signOutReason
        self.onSignUp = onSignUp
        self.onForgotPassword = onForgotPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                AuthHeader(title: "Welcome Back", subtitle: "Log in to see your tasks.")

                if let notice = signOutReason?.notice {
                    MessageBanner(notice, kind: .info)
                        .accessibilityIdentifier("login.notice")
                }
                if let error = model.errorMessage {
                    MessageBanner(error, kind: .error)
                        .accessibilityIdentifier("login.error")
                }

                VStack(spacing: Spacing.large) {
                    FormField("Email", text: $model.email, kind: .email, error: model.emailError, identifier: "login.email")
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                    FormField("Password", text: $model.password, kind: .password, error: model.passwordError, identifier: "login.password")
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)

                    Button("Forgot Password?") { onForgotPassword(model.email) }
                        .frame(maxWidth: .infinity, minHeight: Metrics.minHitTarget, alignment: .trailing)
                        .accessibilityIdentifier("login.forgotPassword")
                }

                PrimaryButton("Log In", isLoading: model.isSubmitting, action: submit)
                    .accessibilityIdentifier("login.submit")

                // Side by side normally; stacked at accessibility sizes so neither part truncates.
                let promptLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Spacing.xs))
                    : AnyLayout(HStackLayout(spacing: Spacing.xs))
                promptLayout { signUpPrompt }
            }
            .padding(Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focus) { previous, _ in
            if let previous { model.didEndEditing(previous) }
        }
    }

    @ViewBuilder
    private var signUpPrompt: some View {
        Text("Don't have an account?")
            .foregroundStyle(Palette.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        Button("Sign Up", action: onSignUp)
            .frame(minHeight: Metrics.minHitTarget)
            .accessibilityIdentifier("login.signUp")
    }

    private func submit() {
        focus = nil
        Task { await model.submit() }
    }
}

private extension SignOutReason {
    var notice: String? {
        switch self {
        case .userInitiated: nil
        case .sessionExpired: AuthError.userTokenExpired.errorDescription
        case .reauthenticationRequired: AuthError.requiresRecentLogin.errorDescription
        }
    }
}

#if DEBUG
#Preview("Empty") {
    NavigationStack {
        LoginView(model: LoginViewModel(auth: FakeAuthService()), signOutReason: nil, onSignUp: {}, onForgotPassword: { _ in })
    }
}

#Preview("Session expired, dark") {
    NavigationStack {
        LoginView(
            model: LoginViewModel(auth: FakeAuthService()),
            signOutReason: .sessionExpired,
            onSignUp: {},
            onForgotPassword: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("AX5, small phone", traits: .fixedLayout(width: 320, height: 568)) {
    NavigationStack {
        LoginView(model: LoginViewModel(auth: FakeAuthService()), signOutReason: nil, onSignUp: {}, onForgotPassword: { _ in })
    }
    .dynamicTypeSize(.accessibility5)
}
#endif
