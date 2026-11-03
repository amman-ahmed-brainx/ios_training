import Foundation
import SwiftData

/// `TaskRepository` backed by `TaskStore`. The store is created off the main actor when the app
/// starts; calls made before it is ready simply wait for it.
struct LocalTaskRepository: TaskRepository {
    private let storeTask: Task<TaskStore, Never>

    init(container: ModelContainer, clock: any AppClock) {
        storeTask = Task { await TaskStore.make(container: container, clock: clock) }
    }

    /// The underlying store, for components that need more than the repository API (sync, export).
    var store: TaskStore {
        get async { await storeTask.value }
    }

    func observeTasks(for userId: String) -> AsyncStream<[TaskItem]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [TaskItem].self, bufferingPolicy: .bufferingNewest(1))
        let forwarding = Task {
            for await tasks in await store.observeTasks(for: userId) {
                continuation.yield(tasks)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
        return stream
    }

    func create(_ draft: TaskDraft, ownerId: String) async throws(TaskRepositoryError) -> TaskItem {
        try await store.create(draft, ownerId: ownerId)
    }

    func update(taskId: String, with draft: TaskDraft, by userId: String) async throws(TaskRepositoryError) {
        try await store.update(taskId: taskId, with: draft, by: userId)
    }

    func setStatus(_ status: TaskStatus, taskId: String, by userId: String) async throws(TaskRepositoryError) {
        try await store.setStatus(status, taskId: taskId, by: userId)
    }

    func delete(taskId: String, by userId: String) async throws(TaskRepositoryError) {
        try await store.delete(taskId: taskId, by: userId)
    }

    func addAttachment(_ attachment: TaskAttachment, toTask taskId: String, by userId: String) async throws(TaskRepositoryError) {
        try await store.addAttachment(attachment, toTask: taskId, by: userId)
    }

    func removeAttachment(id attachmentId: String, fromTask taskId: String, by userId: String) async throws(TaskRepositoryError) {
        try await store.removeAttachment(id: attachmentId, fromTask: taskId, by: userId)
    }

    func deleteAllLocalData() async throws(TaskRepositoryError) {
        try await store.deleteAllLocalData()
    }
}
