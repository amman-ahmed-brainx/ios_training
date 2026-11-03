import SwiftUI

/// Labelled text input with an inline, accessible error message.
struct FormField: View {
    /// Picks keyboard, autofill content type and secure entry together so they never disagree.
    enum Kind {
        case name
        case email
        case password
        case newPassword
        case plain

        var isSecure: Bool { self == .password || self == .newPassword }

        var contentType: UITextContentType? {
            switch self {
            case .name: .name
            case .email: .emailAddress
            case .password: .password
            case .newPassword: .newPassword
            case .plain: nil
            }
        }
    }

    private let title: LocalizedStringKey
    @Binding private var text: String
    private let kind: Kind
    private let error: String?
    private let identifier: String?
    @State private var isRevealed = false

    init(_ title: LocalizedStringKey, text: Binding<String>, kind: Kind = .plain, error: String? = nil, identifier: String? = nil) {
        self.title = title
        self.identifier = identifier
        _text = text
        self.kind = kind
        self.error = error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)

            HStack(spacing: Spacing.small) {
                input
                if kind.isSecure { revealButton }
            }
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Metrics.minHitTarget)
            .background(Palette.card, in: .rect(cornerRadius: Radius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium)
                    .strokeBorder(error == nil ? AnyShapeStyle(.separator) : AnyShapeStyle(Palette.danger),
                                  lineWidth: error == nil ? 1 : 1.5)
            }

            if let error {
                // Icon plus text, so the error never relies on colour alone.
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        Group {
            if kind.isSecure && !isRevealed {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
        }
        .textContentType(kind.contentType)
        .keyboardType(kind == .email ? .emailAddress : .default)
        .textInputAutocapitalization(kind == .name ? .words : .never)
        .autocorrectionDisabled(kind != .name && kind != .plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(ifPresent: identifier)
    }

    private var revealButton: some View {
        Button {
            isRevealed.toggle()
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .frame(minWidth: Metrics.minHitTarget, minHeight: Metrics.minHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.secondaryText)
        .accessibilityLabel(isRevealed ? Text("Hide password") : Text("Show password"))
    }
}

#Preview("States") {
    @Previewable @State var email = "not-an-email"
    @Previewable @State var password = "secret"
    VStack(spacing: Spacing.large) {
        FormField("Email", text: $email, kind: .email, error: "Enter a valid email address, like name@example.com.")
        FormField("Password", text: $password, kind: .password)
    }
    .padding()
}

#Preview("Dark, AX5") {
    @Previewable @State var email = ""
    FormField("Email", text: $email, kind: .email, error: "This field is required.")
        .padding()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
