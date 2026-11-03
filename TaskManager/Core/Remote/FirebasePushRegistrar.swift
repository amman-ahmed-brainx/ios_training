import FirebaseFirestore
import FirebaseMessaging
import UIKit

/// Something that forwards the APNs device token (from the app delegate) to the push provider.
@MainActor
protocol PushRegistering: AnyObject {
    func setAPNsToken(_ token: Data)
}

/// Registers this device for FCM and keeps its token in `userTokens/{uid}.fcmTokens` (owner-only).
/// `FirebaseAppDelegateProxyEnabled` is off, so the APNs token is forwarded by hand.
@MainActor
final class FirebasePushRegistrar: NSObject, PushRegistering, MessagingDelegate, SessionLifecycleObserver {
    private var userId: String?
    private var currentToken: String?

    nonisolated func sessionDidStart(_ session: AuthSession) async {
        await start(for: session.uid)
    }

    nonisolated func sessionWillEnd(uid: String, reason: SignOutReason) async {
        await stop(for: uid, reason: reason)
    }

    func setAPNsToken(_ token: Data) {
        Messaging.messaging().apnsToken = token
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in await self.save(fcmToken) }
    }

    private func start(for uid: String) async {
        userId = uid
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
        // The token itself arrives through `messaging(_:didReceiveRegistrationToken:)`.
        do {
            try await Messaging.messaging().register()
        } catch {
            Log.notifications.error("FCM registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stop(for uid: String, reason: SignOutReason) async {
        defer { userId = nil; currentToken = nil }
        guard let token = currentToken else { return }
        // Only a deliberate sign-out still has credentials to edit the profile.
        if reason == .userInitiated {
            try? await tokens(uid).updateData(["fcmTokens": FieldValue.arrayRemove([token])])
        }
        try? await Messaging.messaging().unregister()
    }

    private func save(_ token: String) async {
        guard let userId, token != currentToken else { return }
        do {
            try await tokens(userId).setData(["fcmTokens": FieldValue.arrayUnion([token])], merge: true)
            currentToken = token
        } catch {
            Log.notifications.error("Saving the FCM token failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func tokens(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("userTokens").document(uid)
    }
}
