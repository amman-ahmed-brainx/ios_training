import Foundation
import SwiftData

/// The only owner of the SwiftData context. Runs on its own serial executor, never the main
/// actor; callers receive `TaskItem` value copies because `@Model` objects are not Sendable.
@ModelActor
actor TaskStore {
    static let maxTitleLength = 200

    private var clock: any AppClock = SystemClock()
    private var subscribers: [UUID: Subscriber] = [:]
    /// Streams that ended before their `subscribe` ran (both hop onto the actor in separate tasks).
    private var endedBeforeSubscribing: Set<UUID> = []

    private struct Subscriber {
        let userId: String
        let continuation: AsyncStream<[TaskItem]>.Continuation
    }

    /// Creates a store on a background executor. A `@ModelActor` created on the main thread can end
    /// up running its work there, so it is always built inside a detached task.
    static func make(container: ModelContainer, clock: any AppClock) async -> TaskStore {
        await Task.detached(priority: .userInitiated) {
            let store = TaskStore(modelContainer: container)
            await store.setClock(clock)
            return store
        }.value
    }

    private func setClock(_ clock: any AppClock) {
        self.clock = clock
    }

    // MARK: - Reading

    nonisolated func observeTasks(for userId: String) -> AsyncStream<[TaskItem]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [TaskItem].self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        Task { await self.subscribe(id: id, userId: userId, continuation: continuation) }
        return stream
    }

    /// Visible (non-deleted) tasks for `userId`.
    func tasks(for userId: String) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.cacheOwnerId == userId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.item)
    }

    /// Number of rows waiting to be pushed, tombstones included.
    func pendingChangeCount(for userId: String) throws -> Int {
        let synced = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.cacheOwnerId == userId && $0.syncStateRaw != synced }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Writing

    func create(_ draft: TaskDraft, ownerId: String) throws(TaskRepositoryError) -> TaskItem {
        let title = try validatedTitle(draft.title)
        let now = clock.now
        let item = TaskItem(
            id: UUID().uuidString,
            title: title,
            notes: draft.notes,
            status: draft.status,
            priority: draft.priority,
            dueDate: draft.dueDate,
            ownerId: ownerId,
            collaboratorIds: [],
            attachments: [],
            createdAt: now,
            updatedAt: now,
            updatedBy: ownerId,
            syncState: .pendingCreate
        )
        modelContext.insert(TaskEntity(item: item, cacheOwnerId: ownerId, statusUpdatedAt: now, pendingSince: now))
        try save(notifying: ownerId)
        return item
    }

    func update(taskId: String, with draft: TaskDraft, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canEditDetails(entity.item, userId: userId) else { throw .notPermitted }
        let title = try validatedTitle(draft.title)
        let now = clock.now
        entity.title = title
        entity.notes = draft.notes
        entity.priority = draft.priority
        entity.dueDate = draft.dueDate
        if entity.status != draft.status {
            entity.status = draft.status
            entity.statusUpdatedAt = now
        }
        markPending(entity, by: userId, at: now)
        try save(notifying: userId)
    }

    func setStatus(_ status: TaskStatus, taskId: String, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canChangeStatus(entity.item, userId: userId) else { throw .notPermitted }
        guard entity.status != status else { return }
        let now = clock.now
        entity.status = status
        entity.statusUpdatedAt = now
        markPending(entity, by: userId, at: now)
        try save(notifying: userId)
    }

    func delete(taskId: String, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canDelete(entity.item, userId: userId) else { throw .notPermitted }
        if entity.syncState == .pendingCreate {
            // Never reached the backend, so there is nothing to tombstone.
            modelContext.delete(entity)
        } else {
            let now = clock.now
            entity.deletedAt = now
            entity.syncState = .pendingDelete
            entity.updatedAt = now
            entity.updatedBy = userId
            if entity.pendingSince == nil { entity.pendingSince = now }
        }
        try save(notifying: userId)
    }

    func deleteAllLocalData() throws(TaskRepositoryError) {
        do {
            try modelContext.delete(model: TaskEntity.self)
            try modelContext.save()
        } catch {
            Log.sync.error("Wiping the local cache failed: \(error.localizedDescription, privacy: .public)")
            throw .storageFailed
        }
        for subscriber in subscribers.values {
            subscriber.continuation.yield([])
        }
    }

    // MARK: - Helpers

    private func visibleEntity(_ taskId: String, for userId: String) throws(TaskRepositoryError) -> TaskEntity {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == taskId && $0.cacheOwnerId == userId && $0.deletedAt == nil }
        )
        let match: TaskEntity?
        do {
            match = try modelContext.fetch(descriptor).first
        } catch {
            throw .storageFailed
        }
        guard let match else { throw .notFound }
        return match
    }

    private func validatedTitle(_ raw: String) throws(TaskRepositoryError) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= Self.maxTitleLength else { throw .invalidTitle }
        return title
    }

    private func markPending(_ entity: TaskEntity, by userId: String, at now: Date) {
        entity.updatedAt = now
        entity.updatedBy = userId
        // A create that has not been pushed yet stays a create; the push sends the latest fields.
        if entity.syncState == .synced { entity.syncState = .pendingUpdate }
        if entity.pendingSince == nil { entity.pendingSince = now }
        entity.nextRetryAt = nil
    }

    /// Saves immediately so a pending change survives a crash, then republishes to observers.
    private func save(notifying userId: String) throws(TaskRepositoryError) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            Log.sync.error("Saving a local change failed: \(error.localizedDescription, privacy: .public)")
            throw .storageFailed
        }
        publish(for: userId)
    }

    private func publish(for userId: String) {
        let targets = subscribers.values.filter { $0.userId == userId }
        guard !targets.isEmpty else { return }
        do {
            let snapshot = try tasks(for: userId)
            for target in targets { target.continuation.yield(snapshot) }
        } catch {
            Log.sync.error("Fetching tasks failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribe(id: UUID, userId: String, continuation: AsyncStream<[TaskItem]>.Continuation) {
        if endedBeforeSubscribing.remove(id) != nil { return }
        subscribers[id] = Subscriber(userId: userId, continuation: continuation)
        publish(for: userId)
    }

    private func unsubscribe(_ id: UUID) {
        if subscribers.removeValue(forKey: id) == nil {
            endedBeforeSubscribing.insert(id)
        }
    }
}
