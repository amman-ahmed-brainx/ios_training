/// Wipes the local task cache when a session ends, so the next user never sees this user's tasks.
struct TaskCacheCleaner: SessionLifecycleObserver {
    let repository: any TaskRepository

    func sessionWillEnd(uid: String, reason: SignOutReason) async {
        do {
            try await repository.deleteAllLocalData()
        } catch {
            // The cache is also scoped by user on every read, so a failed wipe never exposes rows.
            Log.sync.error("Clearing the task cache on sign-out failed: \(error.message, privacy: .public)")
        }
    }
}
