#if DEBUG
import Foundation

/// In-memory backend for previews and `-uitest`: echoes every write back as a snapshot, like Firestore.
actor FakeTaskRemote: TaskRemote {
    private var documents: [String: VersionedTask] = [:]
    private var subscribers: [UUID: (userId: String, continuation: AsyncStream<RemoteTaskSnapshot>.Continuation)] = [:]

    nonisolated func taskSnapshots(for userId: String) -> AsyncStream<RemoteTaskSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: RemoteTaskSnapshot.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        Task { await self.subscribe(id: id, userId: userId, continuation: continuation) }
        return stream
    }

    func save(_ task: VersionedTask) async throws(RemoteError) {
        documents[task.item.id] = task
        broadcast()
    }

    func saveStatus(of task: VersionedTask) async throws(RemoteError) {
        guard var existing = documents[task.item.id] else { throw .notFound }
        existing.item.status = task.item.status
        existing.item.updatedAt = task.item.updatedAt
        existing.item.updatedBy = task.item.updatedBy
        existing.statusUpdatedAt = task.statusUpdatedAt
        documents[task.item.id] = existing
        broadcast()
    }

    func delete(taskId: String) async throws(RemoteError) {
        documents[taskId] = nil
        broadcast()
    }

    private func subscribe(id: UUID, userId: String, continuation: AsyncStream<RemoteTaskSnapshot>.Continuation) {
        subscribers[id] = (userId, continuation)
        continuation.yield(snapshot(for: userId))
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast() {
        for subscriber in subscribers.values {
            subscriber.continuation.yield(snapshot(for: subscriber.userId))
        }
    }

    private func snapshot(for userId: String) -> RemoteTaskSnapshot {
        RemoteTaskSnapshot(tasks: documents.values.filter { $0.item.memberIds.contains(userId) }, isFromCache: false)
    }
}
#endif
