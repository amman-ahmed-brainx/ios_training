import SwiftUI

/// Full-width primary action that swaps its label for a spinner while work is in flight.
struct PrimaryButton: View {
    private let title: LocalizedStringKey
    private let isLoading: Bool
    private let action: () -> Void

    init(_ title: LocalizedStringKey, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Keep the title laid out while loading so the button does not change size.
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(Palette.onAccent)
                }
            }
        }
        .buttonStyle(.primary)
        .disabled(isLoading)
        .accessibilityValue(isLoading ? Text("Loading") : Text(verbatim: ""))
    }
}

#Preview("States") {
    VStack(spacing: Spacing.large) {
        PrimaryButton("Log In") {}
        PrimaryButton("Log In", isLoading: true) {}
        PrimaryButton("Log In") {}.disabled(true)
        Button("Create Account") {}.buttonStyle(.secondary)
    }
    .padding()
}

#Preview("Dark, AX5") {
    VStack(spacing: Spacing.large) {
        PrimaryButton("Log In") {}
        Button("Create Account") {}.buttonStyle(.secondary)
    }
    .padding()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
