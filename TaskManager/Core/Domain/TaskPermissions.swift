/// Who may do what to a task. Mirrors `firebase/firestore.rules` so the UI never offers an action
/// the backend would reject.
enum TaskPermissions {
    static func isMember(_ userId: String, of task: TaskItem) -> Bool {
        task.memberIds.contains(userId)
    }

    /// Title, notes, priority, due date, collaborators, attachments: owner only.
    static func canEditDetails(_ task: TaskItem, userId: String) -> Bool {
        task.ownerId == userId
    }

    /// Collaborators may move a task through its workflow.
    static func canChangeStatus(_ task: TaskItem, userId: String) -> Bool {
        isMember(userId, of: task)
    }

    static func canDelete(_ task: TaskItem, userId: String) -> Bool {
        task.ownerId == userId
    }
}
