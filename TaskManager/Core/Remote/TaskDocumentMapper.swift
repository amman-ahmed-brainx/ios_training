import Foundation

/// Converts between `tasks/{id}` document fields and `VersionedTask`. Pure and SDK-free: the
/// Firestore layer turns `Timestamp`s into `Date`s before calling it, so it is unit-testable.
enum TaskDocumentMapper {
    static func fields(for task: VersionedTask) -> [String: Any] {
        let item = task.item
        var fields: [String: Any] = [
            "title": item.title,
            "notes": item.notes,
            "status": item.status.rawValue,
            "priority": item.priority.rawValue,
            "ownerId": item.ownerId,
            "collaboratorIds": item.collaboratorIds,
            "memberIds": item.memberIds,
            "attachments": item.attachments.map(attachmentFields),
            "createdAt": item.createdAt,
            "updatedAt": item.updatedAt,
            "updatedBy": item.updatedBy,
            "statusUpdatedAt": task.statusUpdatedAt
        ]
        fields["dueDate"] = item.dueDate ?? NSNull()
        return fields
    }

    /// Fields a collaborator is allowed to change (mirrors `firestore.rules`).
    static func statusFields(for task: VersionedTask) -> [String: Any] {
        [
            "status": task.item.status.rawValue,
            "statusUpdatedAt": task.statusUpdatedAt,
            "updatedAt": task.item.updatedAt,
            "updatedBy": task.item.updatedBy
        ]
    }

    /// Tolerant decoding: unknown enum values and missing optional fields fall back to defaults;
    /// only a missing owner or title makes the document unusable.
    static func task(id: String, fields: [String: Any]) -> VersionedTask? {
        guard let ownerId = fields["ownerId"] as? String,
              let title = fields["title"] as? String else { return nil }
        let updatedAt = fields["updatedAt"] as? Date ?? .distantPast
        let item = TaskItem(
            id: id,
            title: title,
            notes: fields["notes"] as? String ?? "",
            status: (fields["status"] as? String).flatMap(TaskStatus.init(rawValue:)) ?? .todo,
            priority: (fields["priority"] as? String).flatMap(TaskPriority.init(rawValue:)) ?? .medium,
            dueDate: fields["dueDate"] as? Date,
            ownerId: ownerId,
            collaboratorIds: fields["collaboratorIds"] as? [String] ?? [],
            attachments: (fields["attachments"] as? [[String: Any]] ?? []).compactMap(attachment),
            createdAt: fields["createdAt"] as? Date ?? updatedAt,
            updatedAt: updatedAt,
            updatedBy: fields["updatedBy"] as? String ?? ownerId,
            syncState: .synced
        )
        return VersionedTask(item: item, statusUpdatedAt: fields["statusUpdatedAt"] as? Date ?? updatedAt)
    }

    private static func attachmentFields(_ attachment: TaskAttachment) -> [String: Any] {
        [
            "id": attachment.id,
            "name": attachment.name,
            "storagePath": attachment.storagePath,
            "size": attachment.size,
            "contentType": attachment.contentType
        ]
    }

    private static func attachment(_ fields: [String: Any]) -> TaskAttachment? {
        guard let id = fields["id"] as? String, let path = fields["storagePath"] as? String else { return nil }
        return TaskAttachment(
            id: id,
            name: fields["name"] as? String ?? id,
            storagePath: path,
            size: (fields["size"] as? NSNumber)?.int64Value ?? 0,
            contentType: fields["contentType"] as? String ?? "application/octet-stream"
        )
    }
}
