/// Public profile of another user, from `users/{uid}`.
struct UserSummary: Equatable, Sendable, Identifiable {
    let id: String
    let email: String
    let displayName: String

    var label: String { displayName.isEmpty ? email : displayName }
}

/// Looks people up for invitations.
protocol UserDirectory: Sendable {
    /// Exact, case-insensitive email match.
    func user(withEmail email: String) async throws -> UserSummary?
    func user(withId id: String) async throws -> UserSummary?
}
