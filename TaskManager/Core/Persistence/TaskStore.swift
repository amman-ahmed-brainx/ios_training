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

    func addAttachment(_ attachment: TaskAttachment, toTask taskId: String, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canEditDetails(entity.item, userId: userId) else { throw .notPermitted }
        entity.attachments = entity.attachments.filter { $0.id != attachment.id } + [attachment]
        markPending(entity, by: userId, at: clock.now)
        try save(notifying: userId)
    }

    func removeAttachment(id attachmentId: String, fromTask taskId: String, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canEditDetails(entity.item, userId: userId) else { throw .notPermitted }
        entity.attachments = entity.attachments.filter { $0.id != attachmentId }
        markPending(entity, by: userId, at: clock.now)
        try save(notifying: userId)
    }

    func addCollaborator(_ collaboratorId: String, toTask taskId: String, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canEditDetails(entity.item, userId: userId) else { throw .notPermitted }
        guard collaboratorId != entity.ownerId, !entity.collaboratorIds.contains(collaboratorId) else { return }
        entity.collaboratorIds.append(collaboratorId)
        markPending(entity, by: userId, at: clock.now)
        try save(notifying: userId)
    }

    func removeCollaborator(_ collaboratorId: String, fromTask taskId: String, by userId: String) throws(TaskRepositoryError) {
        let entity = try visibleEntity(taskId, for: userId)
        guard TaskPermissions.canEditDetails(entity.item, userId: userId) else { throw .notPermitted }
        entity.collaboratorIds.removeAll { $0 == collaboratorId }
        markPending(entity, by: userId, at: clock.now)
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

    // MARK: - Outbox

    /// One row waiting to be pushed.
    struct PendingChange: Sendable {
        enum Kind: Sendable { case save, statusOnly, delete }
        let task: VersionedTask
        let kind: Kind
    }

    /// Pending rows due for a push, oldest first. Rows backing off until later are skipped.
    func pendingChanges(for userId: String, now: Date) throws -> [PendingChange] {
        let synced = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.cacheOwnerId == userId && $0.syncStateRaw != synced },
            sortBy: [SortDescriptor(\.pendingSince)]
        )
        return try modelContext.fetch(descriptor)
            .filter { ($0.nextRetryAt ?? .distantPast) <= now }
            .map { entity in
                let kind: PendingChange.Kind
                if entity.syncState == .pendingDelete {
                    kind = .delete
                } else if entity.ownerId == userId {
                    kind = .save
                } else {
                    // Collaborators may only write the status fields.
                    kind = .statusOnly
                }
                return PendingChange(task: entity.versioned, kind: kind)
            }
    }

    /// Earliest time a backed-off row becomes due, if any.
    func nextRetryDate(for userId: String) throws -> Date? {
        let synced = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.cacheOwnerId == userId && $0.syncStateRaw != synced }
        )
        return try modelContext.fetch(descriptor).compactMap(\.nextRetryAt).min()
    }

    /// Records a successful push. If the row changed again while the push was in flight it stays
    /// pending, so that newer edit is pushed next time.
    func markPushed(_ change: PendingChange, for userId: String) throws(TaskRepositoryError) {
        guard let entity = try entity(change.task.item.id, for: userId) else { return }
        if change.kind == .delete {
            modelContext.delete(entity)
        } else if entity.updatedAt == change.task.item.updatedAt {
            entity.markSynced()
        }
        try save(notifying: userId)
    }

    /// Records a failed push: retryable failures back off exponentially, permanent ones are dropped
    /// (the listener then restores the backend's version).
    func markFailed(_ change: PendingChange, for userId: String, error: RemoteError, now: Date) throws(TaskRepositoryError) {
        guard let entity = try entity(change.task.item.id, for: userId) else { return }
        if error.isRetryable {
            entity.syncAttempts += 1
            entity.nextRetryAt = now.addingTimeInterval(Self.backoff(attempt: entity.syncAttempts))
            entity.lastSyncError = String(describing: error)
        } else if error == .notFound && change.kind != .save {
            // Deleted on the backend: nothing left to update or delete.
            modelContext.delete(entity)
        } else {
            // The backend refused this write (e.g. access was revoked). Retrying won't help, but the
            // change is never silently discarded: it stays pending, parked, with the reason recorded.
            Log.sync.error("A change was rejected by the backend: \(String(describing: error), privacy: .public)")
            entity.syncAttempts += 1
            entity.nextRetryAt = .distantFuture
            entity.lastSyncError = String(describing: error)
        }
        try save(notifying: userId)
    }

    /// 2s, 4s, 8s … capped at 5 minutes.
    static func backoff(attempt: Int) -> TimeInterval {
        min(300, pow(2, Double(min(attempt, 9))))
    }

    private func entity(_ taskId: String, for userId: String) throws(TaskRepositoryError) -> TaskEntity? {
        do {
            return try modelContext.fetch(FetchDescriptor<TaskEntity>(
                predicate: #Predicate { $0.id == taskId && $0.cacheOwnerId == userId }
            )).first
        } catch {
            throw .storageFailed
        }
    }

    // MARK: - Remote merge

    /// Merges the backend's view of the user's tasks into the cache (see `ConflictResolver`).
    func applyRemote(_ snapshot: RemoteTaskSnapshot, for userId: String) throws(TaskRepositoryError) {
        let locals: [TaskEntity]
        do {
            locals = try modelContext.fetch(FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.cacheOwnerId == userId }))
        } catch {
            throw .storageFailed
        }
        let localById = Dictionary(locals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteIds = Set(snapshot.tasks.map(\.item.id))

        for remote in snapshot.tasks {
            guard let entity = localById[remote.item.id] else {
                modelContext.insert(TaskEntity(item: remote.item, cacheOwnerId: userId,
                                               statusUpdatedAt: remote.statusUpdatedAt, pendingSince: nil))
                continue
            }
            switch entity.syncState {
            case .synced:
                entity.apply(remote)
            case .pendingDelete:
                // Our delete is newer intent; the push removes it remotely.
                continue
            case .pendingCreate, .pendingUpdate:
                let outcome = ConflictResolver.resolve(local: entity.versioned, remote: remote)
                entity.apply(outcome.merged)
                if outcome.needsPush {
                    // It exists remotely now, so any later push is an update.
                    entity.syncState = .pendingUpdate
                } else {
                    entity.markSynced()
                }
            }
        }

        // A cached snapshot may be incomplete; only an authoritative one proves a task is gone.
        if !snapshot.isFromCache {
            for entity in locals where entity.syncState == .synced && !remoteIds.contains(entity.id) {
                modelContext.delete(entity)
            }
        }
        try save(notifying: userId)
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
