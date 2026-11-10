#if DEBUG
/// A couple of known people for previews and UI tests.
struct FakeUserDirectory: UserDirectory {
    static let people = [
        UserSummary(id: "uitest-user", email: "test@example.com", displayName: "Test User"),
        UserSummary(id: "uid-grace", email: "grace@example.com", displayName: "Grace Hopper")
    ]

    func user(withEmail email: String) async throws -> UserSummary? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.people.first { $0.email == normalized }
    }

    func user(withId id: String) async throws -> UserSummary? {
        Self.people.first { $0.id == id }
    }
}
#endif
