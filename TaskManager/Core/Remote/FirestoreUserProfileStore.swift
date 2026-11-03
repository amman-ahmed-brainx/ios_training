import FirebaseFirestore
import Foundation

/// Writes `users/{uid}` profiles to Firestore.
struct FirestoreUserProfileStore: UserProfileStore {
    func ensureProfile(for session: AuthSession) async throws {
        let document = Firestore.firestore().collection("users").document(session.uid)
        var fields: [String: Any] = [
            // Lowercased so invite-by-email can match with an equality query.
            "email": session.email.lowercased(),
            "displayName": session.displayName ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        // Only seed on creation. Push tokens live in the owner-only userTokens/{uid} document.
        if try await !document.getDocument().exists {
            fields["createdAt"] = FieldValue.serverTimestamp()
        }
        try await document.setData(fields, merge: true)
    }
}
