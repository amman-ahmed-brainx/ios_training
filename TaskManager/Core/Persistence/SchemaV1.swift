import Foundation
import SwiftData

/// First shipped schema. Models live inside the versioned schema so a future `SchemaV2` can
/// declare changed copies side by side and `TaskManagerMigrationPlan` can map between them.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [TaskEntity.self] }

    /// Local row for a task. Never leaves the `TaskStore` actor; everything else sees `TaskItem`.
    @Model
    final class TaskEntity {
        @Attribute(.unique) var id: String
        /// The signed-in user this cached row belongs to. The cache is wiped on sign-out, and every
        /// fetch is scoped to it, so one user can never see another user's rows.
        var cacheOwnerId: String
        var title: String
        var notes: String
        var statusRaw: String
        var priorityRaw: String
        var dueDate: Date?
        var ownerId: String
        var collaboratorIds: [String]
        /// JSON-encoded `[TaskAttachment]`; a blob keeps the schema simple and the field never needs querying.
        var attachmentsData: Data
        var createdAt: Date
        var updatedAt: Date
        var updatedBy: String
        /// When `status` last changed. Lets sync merge a collaborator's status change field-wise
        /// instead of losing it to an owner's stale offline edit of other fields.
        var statusUpdatedAt: Date

        // MARK: Outbox
        var syncStateRaw: String
        /// Tombstone: set when deleted locally but not yet confirmed by the backend.
        var deletedAt: Date?
        /// Orders the outbox; set when the row first becomes pending.
        var pendingSince: Date?
        var syncAttempts: Int
        var nextRetryAt: Date?
        var lastSyncError: String?

        init(item: TaskItem, cacheOwnerId: String, statusUpdatedAt: Date, pendingSince: Date?) {
            id = item.id
            self.cacheOwnerId = cacheOwnerId
            title = item.title
            notes = item.notes
            statusRaw = item.status.rawValue
            priorityRaw = item.priority.rawValue
            dueDate = item.dueDate
            ownerId = item.ownerId
            collaboratorIds = item.collaboratorIds
            attachmentsData = Self.encode(item.attachments)
            createdAt = item.createdAt
            updatedAt = item.updatedAt
            updatedBy = item.updatedBy
            self.statusUpdatedAt = statusUpdatedAt
            syncStateRaw = item.syncState.rawValue
            deletedAt = nil
            self.pendingSince = pendingSince
            syncAttempts = 0
            nextRetryAt = nil
            lastSyncError = nil
        }
    }
}

typealias TaskEntity = SchemaV1.TaskEntity

extension TaskEntity {
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .pendingUpdate }
        set { syncStateRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var attachments: [TaskAttachment] {
        get { (try? JSONDecoder().decode([TaskAttachment].self, from: attachmentsData)) ?? [] }
        set { attachmentsData = Self.encode(newValue) }
    }

    /// Value copy for use outside the store actor.
    var item: TaskItem {
        TaskItem(
            id: id,
            title: title,
            notes: notes,
            status: status,
            priority: priority,
            dueDate: dueDate,
            ownerId: ownerId,
            collaboratorIds: collaboratorIds,
            attachments: attachments,
            createdAt: createdAt,
            updatedAt: updatedAt,
            updatedBy: updatedBy,
            syncState: syncState
        )
    }

    var versioned: VersionedTask {
        VersionedTask(item: item, statusUpdatedAt: statusUpdatedAt)
    }

    /// Overwrites the task fields (not the outbox bookkeeping) with `task`.
    func apply(_ task: VersionedTask) {
        let item = task.item
        title = item.title
        notes = item.notes
        status = item.status
        priority = item.priority
        dueDate = item.dueDate
        ownerId = item.ownerId
        collaboratorIds = item.collaboratorIds
        attachments = item.attachments
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        updatedBy = item.updatedBy
        statusUpdatedAt = task.statusUpdatedAt
    }

    /// Clears the outbox state after the backend confirmed this row.
    func markSynced() {
        syncState = .synced
        pendingSince = nil
        syncAttempts = 0
        nextRetryAt = nil
        lastSyncError = nil
    }

    static func encode(_ attachments: [TaskAttachment]) -> Data {
        // Encoding plain Codable values cannot fail; an empty blob decodes back to [].
        (try? JSONEncoder().encode(attachments)) ?? Data()
    }
}
