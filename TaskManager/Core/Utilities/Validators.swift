import Foundation

/// A field-level validation failure with a user-facing message.
enum ValidationError: Error, Equatable, Sendable {
    case required
    case invalidEmail
    case passwordTooShort(minimum: Int)
    case passwordNeedsLetterAndDigit
    case passwordsDoNotMatch
    case tooLong(maximum: Int)

    var message: String {
        switch self {
        case .required:
            String(localized: "This field is required.")
        case .invalidEmail:
            String(localized: "Enter a valid email address, like name@example.com.")
        case .passwordTooShort(let minimum):
            String(localized: "Use at least \(minimum) characters.")
        case .passwordNeedsLetterAndDigit:
            String(localized: "Include at least one letter and one number.")
        case .passwordsDoNotMatch:
            String(localized: "Passwords don't match.")
        case .tooLong(let maximum):
            String(localized: "Keep it under \(maximum) characters.")
        }
    }
}

/// Pure input validation shared by the auth forms (and later, invite-by-email).
enum Validators {
    static let minimumPasswordLength = 8

    // Deliberately permissive: one @, a non-empty local part, and a dotted domain.
    // The server is the authority; this only catches typos early.
    // Computed because `Regex` is not Sendable, so it cannot be a stored static.
    private static var emailPattern: Regex<Substring> { /[^\s@]+@[^\s@]+\.[^\s@][^\s@]+/ }

    static func email(_ value: String) -> ValidationError? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .required }
        return trimmed.wholeMatch(of: emailPattern) == nil ? .invalidEmail : nil
    }

    /// Strength rule for new passwords. Login only checks that a password was entered.
    static func newPassword(_ value: String) -> ValidationError? {
        if value.isEmpty { return .required }
        if value.count < minimumPasswordLength { return .passwordTooShort(minimum: minimumPasswordLength) }
        let hasLetter = value.contains(where: \.isLetter)
        let hasDigit = value.contains(where: \.isNumber)
        return hasLetter && hasDigit ? nil : .passwordNeedsLetterAndDigit
    }

    static func confirmation(_ value: String, matches password: String) -> ValidationError? {
        if value.isEmpty { return .required }
        return value == password ? nil : .passwordsDoNotMatch
    }

    static func required(_ value: String) -> ValidationError? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .required : nil
    }
}
