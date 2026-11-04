import Foundation
import Observation

/// One task, kept live from the local store (so remote changes appear while it is open).
@MainActor
@Observable
final class TaskDetailViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded(TaskItem)
        /// Deleted here or elsewhere while open.
        case missing
        /// The local store could not be read at all.
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var actionError: String?

    let taskId: String
    let userId: String
    private let repository: any TaskRepository
    private let clock: any AppClock
    /// The last requested status change; each new one waits for it so taps apply in order.
    private var statusChange: Task<Void, Never>?

    init(taskId: String, repository: any TaskRepository, userId: String, clock: any AppClock) {
        self.taskId = taskId
        self.repository = repository
        self.userId = userId
        self.clock = clock
    }

    var task: TaskItem? {
        if case .loaded(let task) = state { task } else { nil }
    }

    var canEditDetails: Bool { task.map { TaskPermissions.canEditDetails($0, userId: userId) } ?? false }
    var canChangeStatus: Bool { task.map { TaskPermissions.canChangeStatus($0, userId: userId) } ?? false }
    var canDelete: Bool { task.map { TaskPermissions.canDelete($0, userId: userId) } ?? false }
    var isOverdue: Bool { task?.isOverdue(now: clock.now) ?? false }

    func observe() async {
        var receivedAny = false
        for await tasks in repository.observeTasks(for: userId) {
            receivedAny = true
            state = tasks.first { $0.id == taskId }.map(LoadState.loaded) ?? .missing
        }
        // The stream ending before any snapshot means the store is unavailable, not that the task is gone.
        if !receivedAny && !Task.isCancelled {
            state = .failed(String(localized: "This task couldn't be loaded. Restart the app to try again."))
        }
    }

    /// Fire-and-forget entry point for the status picker. Rapid taps are applied in the order
    /// they were made, so the last tap always wins. Deliberately not cancelled when the screen
    /// closes: a status the user tapped must still be saved (a local write, milliseconds).
    func requestStatus(_ status: TaskStatus) {
        let previous = statusChange
        statusChange = Task {
            await previous?.value
            await setStatus(status)
        }
    }

    /// Waits until every requested status change has been applied.
    func waitForStatusChanges() async {
        await statusChange?.value
    }

    func setStatus(_ status: TaskStatus) async {
        do {
            try await repository.setStatus(status, taskId: taskId, by: userId)
        } catch {
            actionError = error.message
        }
    }

    /// - Returns: `true` when the task was deleted and the screen should close.
    func delete() async -> Bool {
        do {
            try await repository.delete(taskId: taskId, by: userId)
            return true
        } catch {
            actionError = error.message
            return false
        }
    }

    func dismissError() {
        actionError = nil
    }
}
