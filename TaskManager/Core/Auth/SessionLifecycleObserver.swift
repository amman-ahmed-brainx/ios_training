/// Something that holds per-user state and must release it when the session ends:
/// listeners, the local cache, the device's push token, pending work.
protocol SessionLifecycleObserver: Sendable {
    /// Called when a user's session begins (sign-in or restored at launch).
    func sessionDidStart(_ session: AuthSession) async

    /// Called before sign-out (while the user is still authenticated, so remote cleanup can run)
    /// and after an expired session (when only local cleanup is possible).
    func sessionWillEnd(uid: String, reason: SignOutReason) async
}

extension SessionLifecycleObserver {
    func sessionDidStart(_ session: AuthSession) async {}
}
