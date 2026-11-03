/// The `users/{uid}` profile: how invitations find users and how pushes find devices.
protocol UserProfileStore: Sendable {
    /// Creates the profile on first sign-in and refreshes email and display name afterwards.
    /// Never overwrites `createdAt` or `fcmTokens`.
    func ensureProfile(for session: AuthSession) async throws
}
