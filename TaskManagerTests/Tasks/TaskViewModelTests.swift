import Foundation
import Testing
@testable import TaskManager

@MainActor
struct TaskListViewModelTests {
    private let repository = MockTaskRepository()
    private let clock = TestClock()

    private func loadedModel(with tasks: [TaskItem]) async -> (TaskListViewModel, Task<Void, Never>) {
        let model = TaskListViewModel(repository: repository, userId: "uid-ada", clock: clock)
        let observing = Task { await model.observe() }
        repository.emit(tasks)
        await eventually { model.loadState == .loaded }
        return (model, observing)
    }

    @Test func startsLoadingThenShowsTheStoresTasks() async {
        let model = TaskListViewModel(repository: repository, userId: "uid-ada", clock: clock)
        #expect(model.loadState == .loading)

        let (loaded, observing) = await loadedModel(with: [.make(title: "One")])

        #expect(loaded.visibleTasks.map(\.title) == ["One"])
        observing.cancel()
    }

    @Test func changingTheQueryRecomputesVisibleTasks() async {
        let (model, observing) = await loadedModel(with: [.make(title: "Report"), .make(title: "Groceries")])

        model.query.searchText = "rep"

        #expect(model.visibleTasks.map(\.title) == ["Report"])
        #expect(model.isFiltering)
        observing.cancel()
    }

    @Test func clearingFiltersKeepsTheSortOrder() async {
        let (model, observing) = await loadedModel(with: [])
        model.query = TaskQuery(status: .done, sort: .priority)

        model.clearFilters()

        #expect(model.query == TaskQuery(sort: .priority))
        observing.cancel()
    }

    @Test(arguments: [(TaskStatus.todo, TaskStatus.done), (.inProgress, .done), (.done, .todo)])
    func toggleCompletionFlipsBetweenDoneAndToDo(from: TaskStatus, to: TaskStatus) async {
        let task = TaskItem.make(id: "t1", status: from)
        let (model, observing) = await loadedModel(with: [task])

        await model.toggleCompletion(of: task)

        #expect(await repository.calls == [.setStatus(to, taskId: "t1", userId: "uid-ada")])
        observing.cancel()
    }

    @Test func failedActionShowsAMessage() async {
        await repository.failNextCalls(with: .notPermitted)
        let task = TaskItem.make(id: "t1")
        let (model, observing) = await loadedModel(with: [task])

        await model.delete(task)

        #expect(model.actionError == TaskRepositoryError.notPermitted.message)
        model.dismissError()
        #expect(model.actionError == nil)
        observing.cancel()
    }

    @Test func countsPendingChanges() async {
        let (model, observing) = await loadedModel(with: [
            .make(syncState: .pendingCreate), .make(syncState: .synced), .make(syncState: .pendingUpdate)
        ])
        #expect(model.pendingChangeCount == 2)
        observing.cancel()
    }

    @Test func permissionsFollowOwnership() async {
        let shared = TaskItem.make(ownerId: "uid-grace", collaboratorIds: ["uid-ada"])
        let (model, observing) = await loadedModel(with: [shared])

        #expect(model.canChangeStatus(shared))
        #expect(!model.canDelete(shared))
        observing.cancel()
    }

    @Test func storeEndingWithoutDataShowsAnError() async {
        let model = TaskListViewModel(repository: repository, userId: "uid-ada", clock: clock)
        repository.finish()

        await model.observe()

        guard case .failed = model.loadState else {
            Issue.record("Expected failed state, got \(model.loadState)")
            return
        }
    }
}

@MainActor
struct TaskEditorViewModelTests {
    private let repository = MockTaskRepository()
    private let clock = TestClock()

    private func editor(for task: TaskItem? = nil, userId: String = "uid-ada") -> TaskEditorViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return TaskEditorViewModel(editing: task, repository: repository, userId: userId, clock: clock, calendar: calendar)
    }

    @Test func blankTitleBlocksSaving() async {
        let model = editor()
        model.title = "   "

        #expect(await model.save() == false)
        #expect(model.titleError == ValidationError.required.message)
        #expect(await repository.calls.isEmpty)
    }

    @Test func overlongTitleIsRejected() async {
        let model = editor()
        model.title = String(repeating: "x", count: TaskStore.maxTitleLength + 1)

        #expect(await model.save() == false)
        #expect(model.titleError == ValidationError.tooLong(maximum: TaskStore.maxTitleLength).message)
    }

    @Test func creatingSendsTheDraft() async {
        let model = editor()
        model.title = "Write report"
        model.priority = .high

        #expect(await model.save())
        #expect(await repository.calls == [.create(.titled("Write report", priority: .high), ownerId: "uid-ada")])
    }

    @Test func editingPrefillsAndUpdates() async {
        let task = TaskItem.make(id: "t1", title: "Old", priority: .low)
        let model = editor(for: task)
        #expect(model.title == "Old")
        #expect(!model.isDirty)

        model.title = "New"
        #expect(model.isDirty)
        #expect(await model.save())
        #expect(await repository.calls == [.update(taskId: "t1", draft: .titled("New", priority: .low), userId: "uid-ada")])
    }

    @Test func collaboratorCanOnlySaveTheStatus() async {
        let task = TaskItem.make(id: "t1", title: "Shared", ownerId: "uid-grace", collaboratorIds: ["uid-ada"])
        let model = editor(for: task)
        #expect(!model.canEditDetails)

        model.status = .inProgress
        #expect(await model.save())
        #expect(await repository.calls == [.setStatus(.inProgress, taskId: "t1", userId: "uid-ada")])
    }

    @Test func turningOnTheDueDateSuggestsTomorrowAtNine() throws {
        let model = editor()

        model.hasDueDate = true

        let due = try #require(model.dueDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(calendar.component(.hour, from: due) == 9)
        #expect(calendar.dateComponents([.day], from: calendar.startOfDay(for: clock.now), to: calendar.startOfDay(for: due)).day == 1)
        #expect(model.draft.dueDate == due)

        model.hasDueDate = false
        #expect(model.draft.dueDate == nil)
    }

    @Test func datePickerDefaultComesFromTheInjectedClock() {
        let model = editor()
        #expect(model.dueDate == nil)

        let shown = model.dueDateSelection
        #expect(shown > clock.now)
        #expect(shown < clock.now.addingTimeInterval(2 * 86_400))

        model.dueDateSelection = clock.now
        #expect(model.dueDate == clock.now)
    }

    @Test func saveFailureShowsMessage() async {
        await repository.failNextCalls(with: .storageFailed)
        let model = editor()
        model.title = "Anything"

        #expect(await model.save() == false)
        #expect(model.errorMessage == TaskRepositoryError.storageFailed.message)
        #expect(!model.isSaving)
    }
}

@MainActor
struct TaskDetailViewModelTests {
    private let repository = MockTaskRepository()

    private func observedModel() async -> (TaskDetailViewModel, Task<Void, Never>) {
        let model = TaskDetailViewModel(taskId: "t1", repository: repository, userId: "uid-ada", clock: TestClock())
        let observing = Task { await model.observe() }
        return (model, observing)
    }

    @Test func followsTheTaskAndNoticesDeletion() async {
        let (model, observing) = await observedModel()

        repository.emit([.make(id: "t1", title: "Live")])
        await eventually { model.task?.title == "Live" }
        #expect(model.canDelete)

        repository.emit([])
        await eventually { model.state == .missing }
        observing.cancel()
    }

    @Test func storeEndingWithoutDataShowsAnErrorNotASpinner() async {
        let model = TaskDetailViewModel(taskId: "t1", repository: repository, userId: "uid-ada", clock: TestClock())
        repository.finish()

        await model.observe()

        guard case .failed = model.state else {
            Issue.record("Expected failed state, got \(model.state)")
            return
        }
    }

    @Test func deleteClosesTheScreenOnSuccess() async {
        let (model, observing) = await observedModel()

        #expect(await model.delete())
        #expect(await repository.calls == [.delete(taskId: "t1", userId: "uid-ada")])
        observing.cancel()
    }

    @Test func rapidStatusTapsApplyInOrder() async {
        let (model, observing) = await observedModel()

        model.requestStatus(.inProgress)
        model.requestStatus(.done)
        model.requestStatus(.todo)
        await model.waitForStatusChanges()

        #expect(await repository.calls == [
            .setStatus(.inProgress, taskId: "t1", userId: "uid-ada"),
            .setStatus(.done, taskId: "t1", userId: "uid-ada"),
            .setStatus(.todo, taskId: "t1", userId: "uid-ada")
        ])
        observing.cancel()
    }

    @Test func statusChangeFailureIsShown() async {
        await repository.failNextCalls(with: .notFound)
        let (model, observing) = await observedModel()

        await model.setStatus(.done)

        #expect(model.actionError == TaskRepositoryError.notFound.message)
        observing.cancel()
    }
}

struct TaskCacheCleanerTests {
    @Test func endingASessionWipesTheCache() async {
        let repository = MockTaskRepository()

        await TaskCacheCleaner(repository: repository).sessionWillEnd(uid: "uid-ada", reason: .userInitiated)

        #expect(await repository.calls == [.deleteAll])
    }
}

@MainActor
struct TaskMemoryLeakTests {
    @Test func taskListViewModelIsReleasedWhenItsViewGoesAway() async {
        let repository = MockTaskRepository()
        weak var weakModel: TaskListViewModel?
        do {
            let model = TaskListViewModel(repository: repository, userId: "uid-ada", clock: TestClock())
            let observing = Task { await model.observe() }
            repository.emit([.make()])
            await eventually { model.loadState == .loaded }
            // The view's `.task` is cancelled on disappear; that must end the observation.
            observing.cancel()
            await observing.value
            weakModel = model
        }
        #expect(weakModel == nil)
    }
}
