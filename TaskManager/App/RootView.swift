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
                switch phase {
                case .active: environment.didBecomeActive()
                case .background: environment.didEnterBackground()
                case .inactive: break
                @unknown default: break
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
            MainView(environment: environment, session: session)
                // A different user gets a fresh view tree (and fresh view models).
                .id(session.uid)
                .transition(.opacity)
        }
    }
}

#if DEBUG
#Preview("Signed in") {
    RootView(environment: .preview)
}
#endif
