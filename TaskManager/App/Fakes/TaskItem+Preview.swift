#if DEBUG
import Foundation

extension TaskItem {
    /// Sample task for previews; the defaults read as a typical owned task.
    static func preview(
        title: String = "Sample task",
        notes: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        dueDate: Date? = Date().addingTimeInterval(86_400),
        ownerId: String = "uitest-user",
        syncState: SyncState = .synced
    ) -> TaskItem {
        TaskItem(
            id: UUID().uuidString,
            title: title,
            notes: notes,
            status: status,
            priority: priority,
            dueDate: dueDate,
            ownerId: ownerId,
            collaboratorIds: [],
            attachments: [],
            createdAt: Date(),
            updatedAt: Date(),
            updatedBy: ownerId,
            syncState: syncState
        )
    }
}
#endif
