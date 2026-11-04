import SwiftUI

/// Signed-out navigation: login at the root, sign-up pushed, password reset as a sheet.
struct AuthFlowView: View {
    private enum Route: Hashable { case signUp }

    /// Wraps the prefilled email so the sheet can be driven by `sheet(item:)`.
    private struct ResetRequest: Identifiable {
        let id = UUID()
        let email: String
    }

    private let environment: AppEnvironment
    private let signOutReason: SignOutReason?
    @State private var path: [Route] = []
    @State private var resetRequest: ResetRequest?

    init(environment: AppEnvironment, signOutReason: SignOutReason?) {
        self.environment = environment
        self.signOutReason = signOutReason
    }

    var body: some View {
        NavigationStack(path: $path) {
            LoginView(
                model: environment.makeLoginViewModel(),
                signOutReason: signOutReason,
                onSignUp: { path.append(.signUp) },
                onForgotPassword: { resetRequest = ResetRequest(email: $0) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .signUp:
                    SignUpView(model: environment.makeSignUpViewModel())
                }
            }
        }
        .sheet(item: $resetRequest) { request in
            ForgotPasswordView(model: environment.makeForgotPasswordViewModel(email: request.email))
        }
    }
}
