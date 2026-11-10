import FirebaseFirestore

/// `UserDirectory` over the `users` collection (email is stored lowercased).
struct FirestoreUserDirectory: UserDirectory {
    private var users: CollectionReference { Firestore.firestore().collection("users") }

    func user(withEmail email: String) async throws -> UserSummary? {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let snapshot = try await users.whereField("email", isEqualTo: normalized).limit(to: 1).getDocuments()
        return snapshot.documents.first.map { Self.summary(id: $0.documentID, data: $0.data()) }
    }

    func user(withId id: String) async throws -> UserSummary? {
        let document = try await users.document(id).getDocument()
        return document.data().map { Self.summary(id: id, data: $0) }
    }

    private static func summary(id: String, data: [String: Any]) -> UserSummary {
        UserSummary(id: id, email: data["email"] as? String ?? "", displayName: data["displayName"] as? String ?? "")
    }
}
