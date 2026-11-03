@testable import TaskManager

/// Records calls and returns scripted failures. Push snapshots to observers with `emit(_:)`.
actor MockTaskRepository: TaskRepository {
    enum Call: Equatable {
        case create(TaskDraft, ownerId: String)
        case update(taskId: String, draft: TaskDraft, userId: String)
        case setStatus(TaskStatus, taskId: String, userId: String)
        case delete(taskId: String, userId: String)
        case deleteAll
        case addAttachment(TaskAttachment, taskId: String, userId: String)
        case removeAttachment(id: String, taskId: String, userId: String)
    }

    private nonisolated let stream: AsyncStream<[TaskItem]>
    private nonisolated let continuation: AsyncStream<[TaskItem]>.Continuation
    private(set) var calls: [Call] = []
    private var failure: TaskRepositoryError?

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: [TaskItem].self)
    }

    nonisolated func emit(_ tasks: [TaskItem]) { continuation.yield(tasks) }
    nonisolated func finish() { continuation.finish() }
    func failNextCalls(with error: TaskRepositoryError) { failure = error }

    nonisolated func observeTasks(for userId: String) -> AsyncStream<[TaskItem]> { stream }

    func create(_ draft: TaskDraft, ownerId: String) async throws(TaskRepositoryError) -> TaskItem {
        calls.append(.create(draft, ownerId: ownerId))
        if let failure { throw failure }
        return .make(title: draft.title, status: draft.status, priority: draft.priority, dueDate: draft.dueDate, ownerId: ownerId)
    }

    func update(taskId: String, with draft: TaskDraft, by userId: String) async throws(TaskRepositoryError) {
        calls.append(.update(taskId: taskId, draft: draft, userId: userId))
        if let failure { throw failure }
    }

    func setStatus(_ status: TaskStatus, taskId: String, by userId: String) async throws(TaskRepositoryError) {
        calls.append(.setStatus(status, taskId: taskId, userId: userId))
        if let failure { throw failure }
    }

    func delete(taskId: String, by userId: String) async throws(TaskRepositoryError) {
        calls.append(.delete(taskId: taskId, userId: userId))
        if let failure { throw failure }
    }

    func addAttachment(_ attachment: TaskAttachment, toTask taskId: String, by userId: String) async throws(TaskRepositoryError) {
        calls.append(.addAttachment(attachment, taskId: taskId, userId: userId))
        if let failure { throw failure }
    }

    func removeAttachment(id attachmentId: String, fromTask taskId: String, by userId: String) async throws(TaskRepositoryError) {
        calls.append(.removeAttachment(id: attachmentId, taskId: taskId, userId: userId))
        if let failure { throw failure }
    }

    func deleteAllLocalData() async throws(TaskRepositoryError) {
        calls.append(.deleteAll)
        if let failure { throw failure }
    }
}
