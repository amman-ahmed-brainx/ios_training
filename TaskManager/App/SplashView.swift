import SwiftUI

/// Shown for the moment it takes to restore the persisted session at launch.
struct SplashView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: "checklist")
                .font(.system(size: iconSize))
                .foregroundStyle(Palette.accent)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.launchBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
        .accessibilityIdentifier("splash")
    }
}

#Preview {
    SplashView()
}
