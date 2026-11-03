/// Last-resort repository when no SwiftData store can be opened at all. The task list shows its
/// error state instead of the app crashing at launch.
struct UnavailableTaskRepository: TaskRepository {
    func observeTasks(for userId: String) -> AsyncStream<[TaskItem]> {
        AsyncStream { $0.finish() }
    }

    func create(_ draft: TaskDraft, ownerId: String) async throws(TaskRepositoryError) -> TaskItem {
        throw .storageFailed
    }

    func update(taskId: String, with draft: TaskDraft, by userId: String) async throws(TaskRepositoryError) {
        throw .storageFailed
    }

    func setStatus(_ status: TaskStatus, taskId: String, by userId: String) async throws(TaskRepositoryError) {
        throw .storageFailed
    }

    func delete(taskId: String, by userId: String) async throws(TaskRepositoryError) {
        throw .storageFailed
    }

    func addAttachment(_ attachment: TaskAttachment, toTask taskId: String, by userId: String) async throws(TaskRepositoryError) {
        throw .storageFailed
    }

    func removeAttachment(id attachmentId: String, fromTask taskId: String, by userId: String) async throws(TaskRepositoryError) {
        throw .storageFailed
    }

    func deleteAllLocalData() async throws(TaskRepositoryError) {}
}
