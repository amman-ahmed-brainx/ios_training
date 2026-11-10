/// What the UI shows about sync.
struct SyncStatus: Equatable, Sendable {
    var isOnline: Bool
    var pendingCount: Int
    var isSyncing: Bool

    static let idle = SyncStatus(isOnline: true, pendingCount: 0, isSyncing: false)
}

/// The sync controls view models use (pull-to-refresh, "Sync Now", the status banner).
protocol SyncControlling: Sendable {
    /// Pushes pending changes now if online.
    func syncNow() async
    /// Emits the current status immediately and after every change.
    func statusUpdates() -> AsyncStream<SyncStatus>
}
