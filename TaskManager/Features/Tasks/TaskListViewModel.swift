import Foundation
import Observation

/// Task list state: the user's tasks from the local store, narrowed by search, filters and sort.
@MainActor
@Observable
final class TaskListViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var tasks: [TaskItem] = []
    /// `tasks` after `query`; recomputed when either changes, never inside `body`.
    private(set) var visibleTasks: [TaskItem] = []
    private(set) var actionError: String?
    var query = TaskQuery() {
        didSet { if query != oldValue { refreshVisible() } }
    }

    let userId: String
    private let repository: any TaskRepository
    private let clock: any AppClock

    init(repository: any TaskRepository, userId: String, clock: any AppClock) {
        self.repository = repository
        self.userId = userId
        self.clock = clock
    }

    /// Local changes not yet confirmed by the backend.
    var pendingChangeCount: Int { tasks.count(where: \.syncState.isPending) }

    /// Whether the list is empty because of search or filters rather than because there are no tasks.
    var isFiltering: Bool {
        query.hasActiveFilters || !query.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Follows the store until the calling task is cancelled (the view's `.task`).
    func observe() async {
        var receivedAny = false
        for await snapshot in repository.observeTasks(for: userId) {
            receivedAny = true
            tasks = snapshot
            loadState = .loaded
            refreshVisible()
        }
        if !receivedAny && !Task.isCancelled {
            loadState = .failed(String(localized: "Your tasks couldn't be loaded. Restart the app to try again."))
        }
    }

    func isOverdue(_ task: TaskItem) -> Bool { task.isOverdue(now: clock.now) }
    func canDelete(_ task: TaskItem) -> Bool { TaskPermissions.canDelete(task, userId: userId) }
    func canChangeStatus(_ task: TaskItem) -> Bool { TaskPermissions.canChangeStatus(task, userId: userId) }

    /// Swipe action: done ↔ to do.
    func toggleCompletion(of task: TaskItem) async {
        await setStatus(task.status == .done ? .todo : .done, for: task)
    }

    func setStatus(_ status: TaskStatus, for task: TaskItem) async {
        do {
            try await repository.setStatus(status, taskId: task.id, by: userId)
        } catch {
            actionError = error.message
        }
    }

    func delete(_ task: TaskItem) async {
        do {
            try await repository.delete(taskId: task.id, by: userId)
        } catch {
            actionError = error.message
        }
    }

    func clearFilters() {
        let sort = query.sort
        query = TaskQuery(sort: sort)
    }

    func dismissError() {
        actionError = nil
    }

    private func refreshVisible() {
        visibleTasks = query.apply(to: tasks, userId: userId, now: clock.now)
    }
}
