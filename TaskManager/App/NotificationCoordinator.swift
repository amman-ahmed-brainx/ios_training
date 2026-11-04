import UserNotifications

/// Presents notifications in the foreground and routes taps (local reminders and FCM pushes,
/// both carrying `taskId`) to that task's detail screen.
@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let router: AppRouter

    init(router: AppRouter) {
        self.router = router
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let taskId = Self.taskId(from: response.notification.request.content.userInfo) else { return }
        await router.showTask(taskId)
    }

    /// The task a notification refers to. Payloads are untrusted: only a plain, non-empty id
    /// without path separators is accepted (it is only ever used to look up the local store).
    nonisolated static func taskId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let taskId = userInfo["taskId"] as? String else { return nil }
        let trimmed = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128, !trimmed.contains("/") else { return nil }
        return trimmed
    }
}
