import SwiftUI

/// Session gate: splash while the persisted session resolves, then the auth flow or the app.
struct RootView: View {
    let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion ? nil : .default, value: environment.session.state)
            .onChange(of: scenePhase) { _, phase in
                // Catch revoked or disabled accounts as soon as the user returns to the app.
                if phase == .active {
                    Task { await environment.session.validateSession() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch environment.session.state {
        case .unknown:
            SplashView()
        case .signedOut(let reason):
            AuthFlowView(environment: environment, signOutReason: reason)
                .transition(.opacity)
        case .signedIn(let session):
            SignedInPlaceholderView(session: session) {
                await environment.session.signOut()
            }
            .transition(.opacity)
        }
    }
}

#if DEBUG
#Preview("Signed in") {
    RootView(environment: .preview)
}
#endif
