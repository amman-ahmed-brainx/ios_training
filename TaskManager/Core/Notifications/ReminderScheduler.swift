import Foundation
import UserNotifications

/// How long before a task's due date its reminder fires.
enum ReminderLeadTime: Int, CaseIterable, Sendable {
    case fifteenMinutes = 900
    case oneHour = 3600
    case oneDay = 86_400

    var interval: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .fifteenMinutes: String(localized: "15 minutes before")
        case .oneHour: String(localized: "1 hour before")
        case .oneDay: String(localized: "1 day before")
        }
    }
}

/// The user's reminder setting, persisted in UserDefaults.
struct ReminderPreferences: Sendable {
    private static let key = "reminderLeadTime"

    var leadTime: ReminderLeadTime {
        get { ReminderLeadTime(rawValue: UserDefaults.standard.integer(forKey: Self.key)) ?? .oneHour }
        nonmutating set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.key) }
    }
}

/// One local notification the app wants scheduled.
struct ScheduledReminder: Equatable, Sendable {
    let identifier: String
    let taskId: String
    let title: String
    let body: String
    let fireDate: Date
}

/// Thin wrapper over `UNUserNotificationCenter`, so scheduling logic is testable.
protocol NotificationScheduling: Sendable {
    func pendingIdentifiers() async -> [String]
    func add(_ reminder: ScheduledReminder) async throws
    func removePending(_ identifiers: [String]) async
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

struct UserNotificationCenterClient: NotificationScheduling {
    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func add(_ reminder: ScheduledReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.taskId
        content.userInfo = ["taskId": reminder.taskId]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
        )
    }

    func removePending(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// Deadline reminders as the app uses them.
protocol ReminderScheduling: Sendable {
    /// Makes the pending reminders exactly match `tasks` (reschedules edits, cancels completed or deleted).
    func reconcile(tasks: [TaskItem], leadTime: ReminderLeadTime) async
    func removeAll() async
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
}

/// Schedules `dueDate − leadTime` reminders, nearest first, within iOS's 64 pending-notification limit.
actor ReminderScheduler: ReminderScheduling {
    static let limit = 64
    static let prefix = "task-reminder-"

    private let center: any NotificationScheduling
    private let clock: any AppClock

    init(center: any NotificationScheduling = UserNotificationCenterClient(), clock: any AppClock) {
        self.center = center
        self.clock = clock
    }

    /// Reminders that should exist for `tasks`; pure, so the 64-limit policy is easy to test.
    static func desiredReminders(for tasks: [TaskItem], leadTime: ReminderLeadTime, now: Date) -> [ScheduledReminder] {
        tasks
            .compactMap { task -> ScheduledReminder? in
                guard task.status != .done, let due = task.dueDate else { return nil }
                let fireDate = due.addingTimeInterval(-leadTime.interval)
                guard fireDate > now else { return nil }
                return ScheduledReminder(
                    identifier: prefix + task.id,
                    taskId: task.id,
                    title: task.title,
                    body: String(localized: "Due \(due.formatted(date: .omitted, time: .shortened))"),
                    fireDate: fireDate
                )
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }

    func reconcile(tasks: [TaskItem], leadTime: ReminderLeadTime) async {
        let desired = Self.desiredReminders(for: tasks, leadTime: leadTime, now: clock.now)
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(Self.prefix) }
        // Replace rather than diff: re-adding with the same identifier updates title and time.
        await center.removePending(ours)
        for reminder in desired {
            do {
                try await center.add(reminder)
            } catch {
                Log.notifications.error("Scheduling a reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func removeAll() async {
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(Self.prefix) }
        await center.removePending(ours)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization()) ?? false
    }
}

/// Keeps reminders in step with the user's tasks: on launch, after every local or synced change,
/// and when the lead time changes. Clears them on sign-out.
actor ReminderCoordinator: SessionLifecycleObserver {
    private let scheduler: any ReminderScheduling
    private let repository: any TaskRepository
    private let preferences: ReminderPreferences
    private var observeTask: Task<Void, Never>?
    private var latest: [TaskItem] = []

    init(scheduler: any ReminderScheduling, repository: any TaskRepository, preferences: ReminderPreferences = ReminderPreferences()) {
        self.scheduler = scheduler
        self.repository = repository
        self.preferences = preferences
    }

    func sessionDidStart(_ session: AuthSession) async {
        observeTask?.cancel()
        let updates = repository.observeTasks(for: session.uid)
        observeTask = Task { [weak self] in
            for await tasks in updates {
                await self?.reconcile(tasks)
            }
        }
    }

    func sessionWillEnd(uid: String, reason: SignOutReason) async {
        observeTask?.cancel()
        observeTask = nil
        latest = []
        await scheduler.removeAll()
    }

    /// Re-applies the current lead time (called after Settings changes it).
    func refresh() async {
        await scheduler.reconcile(tasks: latest, leadTime: preferences.leadTime)
    }

    private func reconcile(_ tasks: [TaskItem]) async {
        latest = tasks
        await scheduler.reconcile(tasks: tasks, leadTime: preferences.leadTime)
    }
}
