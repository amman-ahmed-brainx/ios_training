/// Something that holds per-user state and must release it when the session ends:
/// listeners, the local cache, the device's push token, pending work.
protocol SessionLifecycleObserver: Sendable {
    /// Called before sign-out (while the user is still authenticated, so remote cleanup can run)
    /// and after an expired session (when only local cleanup is possible).
    func sessionWillEnd(uid: String, reason: SignOutReason) async
}
