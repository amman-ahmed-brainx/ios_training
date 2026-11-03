import Foundation
import Observation

/// Create or edit a task. Collaborators editing someone else's task may only change its status.
@MainActor
@Observable
final class TaskEditorViewModel {
    enum Field: Hashable, Sendable { case title }

    var title: String
    var notes: String
    var status: TaskStatus
    var priority: TaskPriority
    var hasDueDate: Bool {
        didSet {
            // Turning the toggle on suggests a sensible time instead of "now".
            if hasDueDate && !oldValue && dueDate == nil { dueDate = defaultDueDate() }
        }
    }
    var dueDate: Date?
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private var validation = InlineValidation<Field>()

    /// `nil` when creating.
    let original: TaskItem?
    let canEditDetails: Bool
    private let userId: String
    private let repository: any TaskRepository
    private let clock: any AppClock
    private let calendar: Calendar

    init(
        editing task: TaskItem?,
        repository: any TaskRepository,
        userId: String,
        clock: any AppClock,
        calendar: Calendar = .current
    ) {
        let draft = task.map(TaskDraft.init) ?? .empty
        original = task
        title = draft.title
        notes = draft.notes
        status = draft.status
        priority = draft.priority
        hasDueDate = draft.dueDate != nil
        dueDate = draft.dueDate
        canEditDetails = task.map { TaskPermissions.canEditDetails($0, userId: userId) } ?? true
        self.userId = userId
        self.repository = repository
        self.clock = clock
        self.calendar = calendar
    }

    var isCreating: Bool { original == nil }

    var titleError: String? { validation.message(for: .title, Self.validateTitle(title)) }

    /// Whether leaving would throw away changes (used to confirm before dismissing).
    var isDirty: Bool {
        draft != (original.map(TaskDraft.init) ?? .empty)
    }

    /// The date picker's value; never `nil`, so the picker always shows a clock-based default.
    var dueDateSelection: Date {
        get { dueDate ?? defaultDueDate() }
        set { dueDate = newValue }
    }

    var draft: TaskDraft {
        TaskDraft(title: title, notes: notes, status: status, priority: priority, dueDate: hasDueDate ? dueDate : nil)
    }

    func didEndEditing(_ field: Field) {
        validation.didEndEditing(field)
    }

    /// - Returns: `true` when saved and the editor should close.
    func save() async -> Bool {
        guard !isSaving else { return false }
        validation.didAttemptSubmit()
        errorMessage = nil
        if canEditDetails && Self.validateTitle(title) != nil { return false }

        isSaving = true
        defer { isSaving = false }
        do {
            if let original {
                if canEditDetails {
                    try await repository.update(taskId: original.id, with: draft, by: userId)
                } else {
                    try await repository.setStatus(status, taskId: original.id, by: userId)
                }
            } else {
                _ = try await repository.create(draft, ownerId: userId)
            }
            return true
        } catch {
            errorMessage = error.message
            return false
        }
    }

    static func validateTitle(_ title: String) -> ValidationError? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .required }
        return trimmed.count > TaskStore.maxTitleLength ? .tooLong(maximum: TaskStore.maxTitleLength) : nil
    }

    /// Tomorrow at 09:00, in the user's calendar.
    private func defaultDueDate() -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock.now) ?? clock.now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
