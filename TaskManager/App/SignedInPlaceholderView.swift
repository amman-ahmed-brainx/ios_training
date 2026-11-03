import SwiftUI

/// Signed-in landing screen until the task list replaces it in the next phase.
struct SignedInPlaceholderView: View {
    let session: AuthSession
    let onSignOut: () async -> Void
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            EmptyStateView(
                systemImage: "checklist",
                title: "Signed In",
                message: "Your tasks will appear here."
            ) {
                Button("Sign Out") {
                    isSigningOut = true
                    Task {
                        await onSignOut()
                        isSigningOut = false
                    }
                }
                .buttonStyle(.secondary)
                .fixedSize()
                .disabled(isSigningOut)
                .accessibilityIdentifier("home.signOut")
            }
            .navigationTitle(Text(verbatim: session.displayName ?? session.email))
        }
    }
}

#Preview {
    SignedInPlaceholderView(session: AuthSession(uid: "1", email: "ada@example.com", displayName: "Ada")) {}
}
