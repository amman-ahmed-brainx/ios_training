import SwiftUI

/// Inline notice above a form: an error from the server, or information such as "session expired".
struct MessageBanner: View {
    enum Kind {
        case error
        case info

        var systemImage: String {
            switch self {
            case .error: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .error: Palette.danger
            case .info: Palette.accent
            }
        }
    }

    private let kind: Kind
    private let message: String

    init(_ message: String, kind: Kind) {
        self.message = message
        self.kind = kind
    }

    var body: some View {
        Label {
            Text(message)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
        }
        .font(.callout)
        .padding(Spacing.medium)
        .background(kind.tint.opacity(0.12), in: .rect(cornerRadius: Radius.medium))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Spacing.large) {
        MessageBanner("Incorrect email or password.", kind: .error)
        MessageBanner("Your session has expired. Please log in again.", kind: .info)
    }
    .padding()
}
