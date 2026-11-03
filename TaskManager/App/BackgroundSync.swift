import BackgroundTasks
import Foundation

/// `BGTaskScheduler` registration and scheduling. Both tasks run the same
/// `SyncEngine.pushPendingChanges()` as the foreground.
///
/// To trigger on a device, pause in the debugger and run:
/// `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.brainxtech.taskmanager.sync"]`
enum BackgroundSync {
    static let refreshIdentifier = "com.brainxtech.taskmanager.sync"
    static let processingIdentifier = "com.brainxtech.taskmanager.sync-processing"

    /// Must run before the app finishes launching.
    static func register(sync: SyncEngine?) {
        for identifier in [refreshIdentifier, processingIdentifier] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
                handle(task, sync: sync)
            }
        }
    }

    static func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.requiresNetworkConnectivity = true
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        for request in [refresh, processing] as [BGTaskRequest] {
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                let identifier = request.identifier
                Log.sync.notice("Scheduling \(identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func handle(_ task: BGTask, sync: SyncEngine?) {
        // Always line up the next run first, so one expiry doesn't end background sync for good.
        schedule()
        let work = Task {
            await sync?.pushPendingChanges()
            return !Task.isCancelled
        }
        // BGTask isn't Sendable, but Apple documents setTaskCompleted and expirationHandler as
        // callable from any thread, and each is used exactly once here.
        nonisolated(unsafe) let task = task
        task.expirationHandler = { work.cancel() }
        Task {
            let succeeded = await work.value
            task.setTaskCompleted(success: succeeded)
        }
    }
}
