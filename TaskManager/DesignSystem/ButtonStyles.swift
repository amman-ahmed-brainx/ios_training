import SwiftUI

/// Filled, full-width call-to-action style.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.onAccent)
            .padding(.vertical, Spacing.medium)
            .padding(.horizontal, Spacing.large)
            .frame(maxWidth: .infinity, minHeight: Metrics.minHitTarget)
            .background(Palette.accent, in: .rect(cornerRadius: Radius.medium))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(.rect)
    }
}

/// Outlined style for secondary actions next to a primary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.accent)
            .padding(.vertical, Spacing.medium)
            .padding(.horizontal, Spacing.large)
            .frame(maxWidth: .infinity, minHeight: Metrics.minHitTarget)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium)
                    .strokeBorder(Palette.accent, lineWidth: 1.5)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
