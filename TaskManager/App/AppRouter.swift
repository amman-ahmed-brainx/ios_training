import Observation

/// Destinations reachable inside the signed-in app.
enum AppRoute: Hashable, Sendable {
    case taskDetail(taskId: String)
}

/// Owns the signed-in `NavigationStack` path, so navigation can be driven from outside the views
/// (notification taps in a later phase) and reset when the session ends.
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func showTask(_ taskId: String) {
        path = [.taskDetail(taskId: taskId)]
    }

    func reset() {
        path.removeAll()
    }
}
