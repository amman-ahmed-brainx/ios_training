import SwiftUI

/// Round floating "+" button, backed by Liquid Glass where available.
struct FloatingAddButton: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 56

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: max(size, Metrics.minHitTarget), height: max(size, Metrics.minHitTarget))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .floatingGlass(in: .circle)
        .accessibilityLabel(Text(label))
    }
}

#Preview {
    FloatingAddButton(label: "Add Task") {}
        .padding()
}
