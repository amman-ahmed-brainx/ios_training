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
        // Only seed these on creation: re-running must not wipe registered push tokens.
        if try await !document.getDocument().exists {
            fields["createdAt"] = FieldValue.serverTimestamp()
            fields["fcmTokens"] = [String]()
        }
        try await document.setData(fields, merge: true)
    }
}
