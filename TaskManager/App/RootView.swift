import SwiftUI

/// Top-level view. A placeholder until the session gate arrives in the auth phase.
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack {
            EmptyStateView(
                systemImage: "checklist",
                title: "Task Manager",
                message: backendMessage
            )
            .accessibilityIdentifier("root.placeholder")
        }
    }

    private var backendMessage: LocalizedStringKey {
        switch environment.backendStatus {
        case .firebase: "Connected to Firebase."
        case .unconfigured: "Firebase is not configured. Running offline."
        case .fake, .notStarted: "Running with sample data."
        }
    }
}

#Preview {
    RootView(environment: .preview)
}
