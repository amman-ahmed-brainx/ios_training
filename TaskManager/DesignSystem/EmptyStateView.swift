import SwiftUI

/// Centered icon, title, message and an optional action, used for empty, error and placeholder screens.
struct EmptyStateView<Actions: View>: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let actions: Actions

    init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

#Preview("With action") {
    EmptyStateView(systemImage: "checklist", title: "No Tasks", message: "Tap + to add your first task.") {
        Button("Add Task") {}.buttonStyle(.primary).fixedSize()
    }
}

#Preview("Dark, AX5") {
    EmptyStateView(systemImage: "wifi.slash", title: "You're Offline", message: "Changes will sync later.")
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
