#if DEBUG
import SwiftUI

/// Debug-only gallery of every token and component, for checking light/dark and Dynamic Type at a glance.
struct DesignSystemCatalog: View {
    private let swatches: [(name: String, color: Color)] = [
        ("accent", Palette.accent),
        ("card", Palette.card),
        ("secondaryText", Palette.secondaryText),
        ("danger", Palette.danger),
        ("statusTodo", Palette.statusTodo),
        ("statusInProgress", Palette.statusInProgress),
        ("statusDone", Palette.statusDone),
        ("priorityLow", Palette.priorityLow),
        ("priorityMedium", Palette.priorityMedium),
        ("priorityHigh", Palette.priorityHigh)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                section("Colours") {
                    ForEach(swatches, id: \.name) { swatch in
                        HStack(spacing: Spacing.medium) {
                            RoundedRectangle(cornerRadius: Radius.small)
                                .fill(swatch.color)
                                .frame(width: Metrics.minHitTarget, height: Metrics.minHitTarget)
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.small).strokeBorder(.separator)
                                }
                            Text(verbatim: swatch.name).font(.body.monospaced())
                        }
                    }
                }
                section("Buttons") {
                    PrimaryButton("Primary") {}
                    Button("Secondary") {}.buttonStyle(.secondary)
                }
                section("Glass") {
                    Label("Floating control", systemImage: "plus")
                        .padding(.horizontal, Spacing.large)
                        .frame(minHeight: Metrics.minHitTarget)
                        .floatingGlass(in: .capsule)
                }
            }
            .padding(Spacing.large)
        }
        .background(Palette.card)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(verbatim: title).font(.headline)
            content()
        }
    }
}

#Preview("Light") {
    DesignSystemCatalog()
}

#Preview("Dark, AX5") {
    DesignSystemCatalog()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
#endif
