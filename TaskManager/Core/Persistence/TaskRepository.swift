import Foundation

/// Why a local task operation was refused.
enum TaskRepositoryError: Error, Equatable, Sendable {
    case notFound
    /// The action is reserved for the owner (or for members, for status changes).
    case notPermitted
    case invalidTitle
    case storageFailed

    var message: String {
        switch self {
        case .notFound: String(localized: "This task no longer exists.")
        case .notPermitted: String(localized: "You don't have permission to do that.")
        case .invalidTitle: String(localized: "A task needs a title.")
        case .storageFailed: String(localized: "Your change couldn't be saved on this device. Please try again.")
        }
    }
}

/// Local, offline-first task storage. Every write is recorded as a pending change for sync.
/// View models depend on this protocol; the live implementation is backed by SwiftData.
protocol TaskRepository: Sendable {
    /// Emits the user's visible tasks now and after every change, local or synced.
    func observeTasks(for userId: String) -> AsyncStream<[TaskItem]>
    func create(_ draft: TaskDraft, ownerId: String) async throws(TaskRepositoryError) -> TaskItem
    /// Owner only: replaces the editable fields.
    func update(taskId: String, with draft: TaskDraft, by userId: String) async throws(TaskRepositoryError)
    /// Owner or collaborator.
    func setStatus(_ status: TaskStatus, taskId: String, by userId: String) async throws(TaskRepositoryError)
    /// Owner only.
    func delete(taskId: String, by userId: String) async throws(TaskRepositoryError)
    /// Removes every cached row, for every user. Used on sign-out.
    func deleteAllLocalData() async throws(TaskRepositoryError)
}
