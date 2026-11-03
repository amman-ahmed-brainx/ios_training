import Foundation
import Testing
import UserNotifications
@testable import TaskManager

actor MockNotificationCenter: NotificationScheduling {
    private(set) var pending: [String: ScheduledReminder] = [:]
    private var others: [String] = ["someone-elses-notification"]

    func pendingIdentifiers() async -> [String] { Array(pending.keys) + others }
    func add(_ reminder: ScheduledReminder) async throws { pending[reminder.identifier] = reminder }
    func removePending(_ identifiers: [String]) async {
        identifiers.forEach { pending[$0] = nil }
        others.removeAll { identifiers.contains($0) }
    }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func remainingOthers() -> [String] { others }
}

struct ReminderSchedulerTests {
    private let clock = TestClock()

    @Test func schedulesDueMinusLeadTimeAndSkipsDoneOrPast() {
        let now = clock.now
        let tasks = [
            TaskItem.make(id: "soon", dueDate: now.addingTimeInterval(7200)),
            TaskItem.make(id: "done", status: .done, dueDate: now.addingTimeInterval(7200)),
            TaskItem.make(id: "past", dueDate: now.addingTimeInterval(1800)),
            TaskItem.make(id: "none")
        ]
        let reminders = ReminderScheduler.desiredReminders(for: tasks, leadTime: .oneHour, now: now)
        #expect(reminders.map(\.taskId) == ["soon"])
        #expect(reminders.first?.fireDate == now.addingTimeInterval(3600))
    }

    @Test func keepsOnlyTheNearest64() {
        let now = clock.now
        let tasks = (0..<100).map { TaskItem.make(id: "t\($0)", dueDate: now.addingTimeInterval(TimeInterval(7200 + $0 * 60))) }
        let reminders = ReminderScheduler.desiredReminders(for: tasks.shuffled(), leadTime: .oneHour, now: now)
        #expect(reminders.count == 64)
        #expect(reminders.first?.taskId == "t0")
        #expect(reminders.last?.taskId == "t63")
    }

    @Test func reconcileReschedulesCancelsAndLeavesOtherNotificationsAlone() async {
        let center = MockNotificationCenter()
        let scheduler = ReminderScheduler(center: center, clock: clock)
        let due = clock.now.addingTimeInterval(86_400)

        await scheduler.reconcile(tasks: [.make(id: "a", dueDate: due), .make(id: "b", dueDate: due)], leadTime: .oneHour)
        #expect(await center.pending.count == 2)

        // "a" completed, "b" moved: a is cancelled, b rescheduled.
        await scheduler.reconcile(tasks: [.make(id: "a", status: .done, dueDate: due),
                                          .make(id: "b", dueDate: due.addingTimeInterval(600))], leadTime: .oneHour)
        let pending = await center.pending
        #expect(pending.keys.sorted() == ["task-reminder-b"])
        #expect(pending["task-reminder-b"]?.fireDate == due.addingTimeInterval(600 - 3600))
        #expect(await center.remainingOthers() == ["someone-elses-notification"])

        await scheduler.removeAll()
        #expect(await center.pending.isEmpty)
    }
}

@MainActor
struct InviteCollaboratorViewModelTests {
    private let repository = MockTaskRepository()

    private func model(collaborators: [String] = []) -> InviteCollaboratorViewModel {
        InviteCollaboratorViewModel(
            task: .make(id: "t1", ownerId: "uitest-user", collaboratorIds: collaborators),
            userId: "uitest-user",
            repository: repository,
            directory: FakeUserDirectory()
        )
    }

    @Test func invitesAKnownUser() async {
        let model = model()
        model.email = " Grace@Example.com "

        await model.invite()

        #expect(await repository.calls == [.addCollaborator("uid-grace", taskId: "t1")])
        #expect(model.collaborators.map(\.id) == ["uid-grace"])
        #expect(model.email.isEmpty)
    }

    @Test func unknownEmailIsReported() async {
        let model = model()
        model.email = "nobody@example.com"
        await model.invite()
        guard case .error = model.message else { Issue.record("Expected an error"); return }
        #expect(await repository.calls.isEmpty)
    }

    @Test func invitingYourselfIsRejected() async {
        let model = model()
        model.email = "test@example.com"
        await model.invite()
        #expect(model.message == .error(String(localized: "You already own this task.")))
    }

    @Test func existingCollaboratorIsRejected() async {
        let model = model(collaborators: ["uid-grace"])
        model.email = "grace@example.com"
        await model.invite()
        guard case .error = model.message else { Issue.record("Expected an error"); return }
        #expect(await repository.calls.isEmpty)
    }

    @Test func removingACollaborator() async {
        let model = model(collaborators: ["uid-grace"])
        await model.loadCollaborators()
        guard let grace = model.collaborators.first else { Issue.record("Not loaded"); return }

        await model.remove(grace)

        #expect(await repository.calls == [.removeCollaborator("uid-grace", taskId: "t1")])
        #expect(model.collaborators.isEmpty)
    }
}

struct NotificationPayloadTests {
    @Test func extractsTheTaskId() {
        #expect(NotificationCoordinator.taskId(from: ["taskId": "abc-123"]) == "abc-123")
    }

    @Test func rejectsMissingOrMalformedIds() {
        #expect(NotificationCoordinator.taskId(from: [:]) == nil)
        #expect(NotificationCoordinator.taskId(from: ["taskId": ""]) == nil)
        #expect(NotificationCoordinator.taskId(from: ["taskId": 42]) == nil)
        #expect(NotificationCoordinator.taskId(from: ["taskId": "../etc"]) == nil)
    }
}
