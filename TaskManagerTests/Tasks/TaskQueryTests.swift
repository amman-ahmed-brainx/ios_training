import Foundation
import Testing
@testable import TaskManager

struct TaskQueryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func titles(_ query: TaskQuery, _ tasks: [TaskItem], userId: String = "uid-ada") -> [String] {
        query.apply(to: tasks, userId: userId, now: now, calendar: calendar).map(\.title)
    }

    @Test func searchMatchesTitleAndNotesIgnoringCaseAndDiacritics() {
        let tasks = [
            TaskItem.make(title: "Café visit"),
            TaskItem.make(title: "Groceries", notes: "Buy CAFE beans"),
            TaskItem.make(title: "Unrelated")
        ]
        let query = TaskQuery(searchText: " cafe ")
        #expect(Set(titles(query, tasks)) == ["Café visit", "Groceries"])
    }

    @Test func filtersByStatusAndPriority() {
        let tasks = [
            TaskItem.make(title: "A", status: .done, priority: .high),
            TaskItem.make(title: "B", status: .done, priority: .low),
            TaskItem.make(title: "C", status: .todo, priority: .high)
        ]
        #expect(titles(TaskQuery(status: .done, priority: .high), tasks) == ["A"])
    }

    @Test func overdueExcludesCompletedAndFutureTasks() {
        let tasks = [
            TaskItem.make(title: "Late", dueDate: now.addingTimeInterval(-60)),
            TaskItem.make(title: "Late but done", status: .done, dueDate: now.addingTimeInterval(-60)),
            TaskItem.make(title: "Later", dueDate: now.addingTimeInterval(60)),
            TaskItem.make(title: "No date")
        ]
        #expect(titles(TaskQuery(due: .overdue), tasks) == ["Late"])
    }

    @Test func dueTodayUsesTheCalendarDay() {
        let startOfDay = calendar.startOfDay(for: now)
        let tasks = [
            TaskItem.make(title: "This morning", dueDate: startOfDay.addingTimeInterval(60)),
            TaskItem.make(title: "Tomorrow", dueDate: startOfDay.addingTimeInterval(86_400 + 60))
        ]
        #expect(titles(TaskQuery(due: .dueToday), tasks) == ["This morning"])
    }

    @Test func ownershipSplitsMineFromShared() {
        let tasks = [
            TaskItem.make(title: "Mine", ownerId: "uid-ada"),
            TaskItem.make(title: "Shared", ownerId: "uid-grace", collaboratorIds: ["uid-ada"])
        ]
        #expect(titles(TaskQuery(ownership: .mine), tasks) == ["Mine"])
        #expect(titles(TaskQuery(ownership: .sharedWithMe), tasks) == ["Shared"])
    }

    @Test func sortByDueDatePutsUndatedTasksLast() {
        let tasks = [
            TaskItem.make(title: "Undated"),
            TaskItem.make(title: "Later", dueDate: now.addingTimeInterval(200)),
            TaskItem.make(title: "Sooner", dueDate: now.addingTimeInterval(100))
        ]
        #expect(titles(TaskQuery(sort: .dueDate), tasks) == ["Sooner", "Later", "Undated"])
    }

    @Test func sortByPriorityIsHighestFirst() {
        let tasks = [
            TaskItem.make(title: "Low", priority: .low),
            TaskItem.make(title: "High", priority: .high),
            TaskItem.make(title: "Medium", priority: .medium)
        ]
        #expect(titles(TaskQuery(sort: .priority), tasks) == ["High", "Medium", "Low"])
    }

    @Test func sortByUpdatedIsNewestFirstWithStableTieBreak() {
        let tasks = [
            TaskItem.make(id: "b", title: "Old", updatedAt: now.addingTimeInterval(-100)),
            TaskItem.make(id: "z", title: "New", updatedAt: now),
            TaskItem.make(id: "a", title: "New twin", updatedAt: now)
        ]
        #expect(titles(TaskQuery(sort: .updated), tasks) == ["New twin", "New", "Old"])
    }

    @Test func activeFiltersIgnoreSearchAndSort() {
        #expect(!TaskQuery(searchText: "x", sort: .priority).hasActiveFilters)
        #expect(TaskQuery(due: .overdue).hasActiveFilters)
    }
}

struct TaskPermissionsTests {
    private let task = TaskItem.make(ownerId: "uid-ada", collaboratorIds: ["uid-grace"])

    @Test func ownerCanDoEverything() {
        #expect(TaskPermissions.canEditDetails(task, userId: "uid-ada"))
        #expect(TaskPermissions.canChangeStatus(task, userId: "uid-ada"))
        #expect(TaskPermissions.canDelete(task, userId: "uid-ada"))
    }

    @Test func collaboratorCanOnlyChangeStatus() {
        #expect(!TaskPermissions.canEditDetails(task, userId: "uid-grace"))
        #expect(TaskPermissions.canChangeStatus(task, userId: "uid-grace"))
        #expect(!TaskPermissions.canDelete(task, userId: "uid-grace"))
    }

    @Test func strangerCanDoNothing() {
        #expect(!TaskPermissions.canEditDetails(task, userId: "uid-eve"))
        #expect(!TaskPermissions.canChangeStatus(task, userId: "uid-eve"))
        #expect(!TaskPermissions.canDelete(task, userId: "uid-eve"))
    }

    @Test func memberIdsListTheOwnerOnce() {
        let odd = TaskItem.make(ownerId: "uid-ada", collaboratorIds: ["uid-ada", "uid-grace"])
        #expect(odd.memberIds == ["uid-ada", "uid-grace"])
    }
}
