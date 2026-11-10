import SwiftUI

/// App mark, title and subtitle shown at the top of each auth screen.
struct AuthHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "checklist")
                .font(.system(size: iconSize))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.large)
    }
}
