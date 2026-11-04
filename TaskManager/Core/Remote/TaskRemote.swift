import Foundation

/// A task plus the clock sync needs to merge `status` independently of the other fields.
struct VersionedTask: Equatable, Sendable {
    var item: TaskItem
    var statusUpdatedAt: Date
}

/// The user's tasks as last seen by the backend.
struct RemoteTaskSnapshot: Sendable {
    let tasks: [VersionedTask]
    /// `true` when served from the SDK's offline cache; absent tasks may then just be unknown.
    let isFromCache: Bool
}

/// Backend failures, classified for retry decisions.
enum RemoteError: Error, Equatable, Sendable {
    case permissionDenied
    case notFound
    case unavailable
    case unauthenticated
    case unknown

    /// Worth retrying with backoff (offline, throttled, transient server errors).
    var isRetryable: Bool {
        switch self {
        // Unauthenticated usually means an expired token the SDK refreshes on the next attempt.
        case .unavailable, .unknown, .unauthenticated: true
        case .permissionDenied, .notFound: false
        }
    }
}

/// Remote task storage. Firestore in production; an in-memory fake in previews and UI tests.
/// Every write is idempotent (fixed document ids), so a retried push is harmless.
protocol TaskRemote: Sendable {
    /// Live snapshots of every task where `memberIds` contains `userId`.
    func taskSnapshots(for userId: String) -> AsyncStream<RemoteTaskSnapshot>
    /// Owner write of the whole document.
    func save(_ task: VersionedTask) async throws(RemoteError)
    /// Collaborator-safe write touching only `status`, `statusUpdatedAt`, `updatedAt`, `updatedBy`.
    func saveStatus(of task: VersionedTask) async throws(RemoteError)
    func delete(taskId: String) async throws(RemoteError)
}
