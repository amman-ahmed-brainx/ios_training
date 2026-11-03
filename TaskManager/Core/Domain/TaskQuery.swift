import Foundation

/// Search, filter and sort applied to the task list. Pure, so it is cheap to unit test.
struct TaskQuery: Equatable, Sendable {
    enum DueFilter: String, CaseIterable, Sendable {
        case any
        case overdue
        case dueToday

        var title: String {
            switch self {
            case .any: String(localized: "Any Due Date")
            case .overdue: String(localized: "Overdue")
            case .dueToday: String(localized: "Due Today")
            }
        }
    }

    enum Ownership: String, CaseIterable, Sendable {
        case all
        case mine
        case sharedWithMe

        var title: String {
            switch self {
            case .all: String(localized: "All Tasks")
            case .mine: String(localized: "Mine")
            case .sharedWithMe: String(localized: "Shared with Me")
            }
        }
    }

    enum Sort: String, CaseIterable, Sendable {
        case dueDate
        case priority
        case updated

        var title: String {
            switch self {
            case .dueDate: String(localized: "Due Date")
            case .priority: String(localized: "Priority")
            case .updated: String(localized: "Recently Updated")
            }
        }
    }

    var searchText = ""
    var status: TaskStatus?
    var priority: TaskPriority?
    var due = DueFilter.any
    var ownership = Ownership.all
    var sort = Sort.dueDate

    /// Whether anything other than search and sort narrows the list.
    var hasActiveFilters: Bool {
        status != nil || priority != nil || due != .any || ownership != .all
    }

    func apply(to tasks: [TaskItem], userId: String, now: Date, calendar: Calendar = .current) -> [TaskItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks
            .filter { task in
                matchesSearch(task, needle: needle)
                    && (status.map { task.status == $0 } ?? true)
                    && (priority.map { task.priority == $0 } ?? true)
                    && matchesDue(task, now: now, calendar: calendar)
                    && matchesOwnership(task, userId: userId)
            }
            .sorted(by: comparator)
    }

    private func matchesSearch(_ task: TaskItem, needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return task.title.localizedStandardContains(needle) || task.notes.localizedStandardContains(needle)
    }

    private func matchesDue(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        switch due {
        case .any: true
        case .overdue: task.isOverdue(now: now)
        case .dueToday: task.dueDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
    }

    private func matchesOwnership(_ task: TaskItem, userId: String) -> Bool {
        switch ownership {
        case .all: true
        case .mine: task.ownerId == userId
        case .sharedWithMe: task.ownerId != userId
        }
    }

    /// Primary key from `sort`; ties fall back to most recently updated, then id, so order is stable.
    private func comparator(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch sort {
        case .dueDate:
            // Tasks without a due date go last.
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        case .priority:
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        case .updated:
            break
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id < rhs.id
    }
}
