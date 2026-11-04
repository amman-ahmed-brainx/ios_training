import Foundation
import os
@testable import TaskManager

/// A clock the test controls. Sendable through the lock, so it can be shared with actors.
final class TestClock: AppClock {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

extension TaskDraft {
    static func titled(_ title: String, status: TaskStatus = .todo, priority: TaskPriority = .medium, dueDate: Date? = nil) -> TaskDraft {
        TaskDraft(title: title, notes: "", status: status, priority: priority, dueDate: dueDate)
    }
}

extension TaskItem {
    /// Minimal task for pure logic tests.
    static func make(
        id: String = UUID().uuidString,
        title: String = "Task",
        notes: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        dueDate: Date? = nil,
        ownerId: String = "uid-ada",
        collaboratorIds: [String] = [],
        updatedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        syncState: SyncState = .synced
    ) -> TaskItem {
        TaskItem(
            id: id, title: title, notes: notes, status: status, priority: priority, dueDate: dueDate,
            ownerId: ownerId, collaboratorIds: collaboratorIds, attachments: [],
            createdAt: updatedAt, updatedAt: updatedAt, updatedBy: ownerId, syncState: syncState
        )
    }
}
