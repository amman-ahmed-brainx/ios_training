import Foundation

/// Backend-independent auth failures, with user-facing messages.
enum AuthError: Error, Equatable, Sendable {
    case invalidEmail
    case wrongCredentials
    case emailAlreadyInUse
    case weakPassword
    case network
    case tooManyRequests
    case userTokenExpired
    case invalidUserToken
    case userDisabled
    case requiresRecentLogin
    case notSignedIn
    /// Live mode without `GoogleService-Info.plist`.
    case notConfigured
    case unknown
}

extension AuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            String(localized: "That email address doesn't look right.")
        case .wrongCredentials:
            String(localized: "Incorrect email or password.")
        case .emailAlreadyInUse:
            String(localized: "An account with this email already exists.")
        case .weakPassword:
            String(localized: "Choose a stronger password.")
        case .network:
            String(localized: "You appear to be offline. Check your connection and try again.")
        case .tooManyRequests:
            String(localized: "Too many attempts. Wait a moment and try again.")
        case .userTokenExpired, .invalidUserToken:
            String(localized: "Your session has expired. Please log in again.")
        case .userDisabled:
            String(localized: "This account has been disabled.")
        case .requiresRecentLogin:
            String(localized: "For your security, please log in again to continue.")
        case .notSignedIn:
            String(localized: "You're not signed in.")
        case .notConfigured:
            String(localized: "Sign-in is unavailable because the app isn't connected to a server.")
        case .unknown:
            String(localized: "Something went wrong. Please try again.")
        }
    }
}
