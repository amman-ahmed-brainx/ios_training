import Foundation

/// Workflow state of a task.
enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case inProgress
    case done

    var title: String {
        switch self {
        case .todo: String(localized: "To Do")
        case .inProgress: String(localized: "In Progress")
        case .done: String(localized: "Done")
        }
    }

    var systemImage: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Sendable, Comparable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        }
    }

    var systemImage: String {
        switch self {
        case .low: "arrow.down"
        case .medium: "equal"
        case .high: "exclamationmark"
        }
    }

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Where a local change stands relative to the backend.
enum SyncState: String, Codable, Sendable {
    case synced
    case pendingCreate
    case pendingUpdate
    case pendingDelete

    var isPending: Bool { self != .synced }
}

/// File attached to a task; the bytes live in Cloud Storage at `storagePath`.
struct TaskAttachment: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var storagePath: String
    var size: Int64
    var contentType: String
}

/// A task as the app sees it: a Sendable value copy of the SwiftData row, safe to pass between actors.
struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var title: String
    var notes: String
    var status: TaskStatus
    var priority: TaskPriority
    var dueDate: Date?
    var ownerId: String
    /// Empty for tasks created on this device until the invite flow and Firestore sync (later
    /// phases) add collaborators; permissions and filters already handle non-empty lists.
    var collaboratorIds: [String]
    var attachments: [TaskAttachment]
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var syncState: SyncState

    /// Everyone allowed to read the task; mirrors the Firestore `memberIds` field.
    var memberIds: [String] { [ownerId] + collaboratorIds.filter { $0 != ownerId } }

    func isOverdue(now: Date) -> Bool {
        guard let dueDate, status != .done else { return false }
        return dueDate < now
    }
}

/// The user-editable fields of a task, as entered in the editor.
struct TaskDraft: Equatable, Sendable {
    var title: String
    var notes: String
    var status: TaskStatus
    var priority: TaskPriority
    var dueDate: Date?

    static let empty = TaskDraft(title: "", notes: "", status: .todo, priority: .medium, dueDate: nil)

    init(title: String, notes: String, status: TaskStatus, priority: TaskPriority, dueDate: Date?) {
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
    }

    init(_ task: TaskItem) {
        self.init(title: task.title, notes: task.notes, status: task.status, priority: task.priority, dueDate: task.dueDate)
    }
}
