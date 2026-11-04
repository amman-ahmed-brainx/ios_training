import Foundation

/// Keeps the local store and the backend in step for the signed-in user.
/// - Incoming: follows the remote snapshot listener and merges every snapshot into `TaskStore`.
/// - Outgoing: pushes the outbox in order when online, after every local change, on demand,
///   and from background tasks. One failing row never blocks the others.
actor SyncEngine: SessionLifecycleObserver, SyncControlling {
    private let remote: any TaskRemote
    private let repository: LocalTaskRepository
    private let network: NetworkMonitor
    private let clock: any AppClock
    private let storage: (any AttachmentStorage)?
    private var userId: String?
    private var tasks: [Task<Void, Never>] = []
    private var retryTask: Task<Void, Never>?
    /// The running push, so callers (sign-out in particular) can wait for it instead of skipping.
    private var pushPass: Task<Void, Never>?
    private var pushRequested = false
    private var status = SyncStatus.idle
    private var statusSubscribers: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    init(
        remote: any TaskRemote,
        repository: LocalTaskRepository,
        storage: (any AttachmentStorage)?,
        network: NetworkMonitor = NetworkMonitor(),
        clock: any AppClock
    ) {
        self.remote = remote
        self.repository = repository
        self.storage = storage
        self.network = network
        self.clock = clock
    }

    // MARK: Session

    func sessionDidStart(_ session: AuthSession) async {
        start(for: session.uid)
    }

    func sessionWillEnd(uid: String, reason: SignOutReason) async {
        // On a deliberate sign-out, try once to push what's pending before the cache is wiped.
        if reason == .userInitiated && status.isOnline {
            await pushPendingChanges()
        }
        stop()
    }

    /// Starts listening, pushing and watching connectivity for `userId`.
    func start(for userId: String) {
        stop()
        self.userId = userId
        let snapshots = remote.taskSnapshots(for: userId)
        let localChanges = repository.observeTasks(for: userId)
        let onlineUpdates = network.onlineUpdates()
        let repository = repository

        tasks.append(Task {
            let store = await repository.store
            for await snapshot in snapshots {
                do {
                    try await store.applyRemote(snapshot, for: userId)
                } catch {
                    Log.sync.error("Merging a remote snapshot failed: \(String(describing: error), privacy: .public)")
                }
            }
        })
        tasks.append(Task { [weak self] in
            for await _ in localChanges {
                await self?.requestPush()
            }
        })
        tasks.append(Task { [weak self] in
            for await isOnline in onlineUpdates {
                await self?.setOnline(isOnline)
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        retryTask?.cancel()
        retryTask = nil
        userId = nil
        update { $0.pendingCount = 0 }
    }

    // MARK: SyncControlling

    func syncNow() async {
        await pushPendingChanges()
    }

    nonisolated func statusUpdates() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: SyncStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        Task { await self.addSubscriber(id, continuation) }
        return stream
    }

    // MARK: Pushing

    /// Pushes every due pending change once and returns when that push has finished. Safe to call
    /// from anywhere, including background tasks.
    func pushPendingChanges() async {
        if let running = pushPass {
            pushRequested = true
            await Self.wait(for: running)
            // That push stopped early because its session ended; push this session's changes now.
            if pushRequested && !Task.isCancelled { await pushPendingChanges() }
            return
        }
        guard let userId, status.isOnline else { return }
        let pass = Task { await self.runPushPasses(for: userId) }
        pushPass = pass
        await Self.wait(for: pass)
    }

    /// Waits for `pass`, cancelling it if the caller is cancelled (e.g. a background task's time
    /// running out), since an unstructured task doesn't inherit the caller's cancellation.
    private static func wait(for pass: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await pass.value
        } onCancel: {
            pass.cancel()
        }
    }

    private func runPushPasses(for userId: String) async {
        update { $0.isSyncing = true }
        defer {
            // Cleared before the task completes, so anyone awaiting it sees no running push.
            pushPass = nil
            update { $0.isSyncing = false }
        }

        let store = await repository.store
        // Requests that arrive during any await below (including the bookkeeping) trigger another pass.
        repeat {
            pushRequested = false
            let changes: [TaskStore.PendingChange]
            do {
                changes = try await store.pendingChanges(for: userId, now: clock.now)
            } catch {
                Log.sync.error("Reading the outbox failed: \(String(describing: error), privacy: .public)")
                changes = []
            }
            for change in changes where self.userId == userId && !Task.isCancelled {
                await push(change, store: store, userId: userId)
            }
            // The session ended mid-push: leave its status and retries alone.
            guard self.userId == userId else { return }
            await refreshPendingCount(store: store, userId: userId)
            await scheduleRetry(store: store, userId: userId)
        } while pushRequested && self.userId == userId && !Task.isCancelled
    }

    private func push(_ change: TaskStore.PendingChange, store: TaskStore, userId: String) async {
        do {
            switch change.kind {
            case .save: try await remote.save(change.task)
            case .statusOnly: try await remote.saveStatus(of: change.task)
            case .delete:
                try await remote.delete(taskId: change.task.item.id)
                await deleteStoredFiles(of: change.task.item)
            }
            try await store.markPushed(change, for: userId)
        } catch let error as RemoteError {
            Log.sync.notice("Push failed for a task: \(String(describing: error), privacy: .public)")
            try? await store.markFailed(change, for: userId, error: error, now: clock.now)
        } catch {
            Log.sync.error("Recording a push result failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Best effort: an orphaned file only costs storage, and only members could ever read it.
    private func deleteStoredFiles(of task: TaskItem) async {
        guard let storage else { return }
        for attachment in task.attachments {
            do {
                try await storage.delete(attachment.storagePath)
            } catch {
                Log.uploads.notice("Deleting a stored attachment failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func requestPush() async {
        await pushPendingChanges()
    }

    private func setOnline(_ isOnline: Bool) async {
        let cameOnline = isOnline && !status.isOnline
        update { $0.isOnline = isOnline }
        if cameOnline { await pushPendingChanges() }
    }

    /// Wakes up when the earliest backed-off row becomes due.
    private func scheduleRetry(store: TaskStore, userId: String) async {
        retryTask?.cancel()
        let next: Date?
        do {
            next = try await store.nextRetryDate(for: userId)
        } catch {
            Log.sync.error("Reading retry times failed: \(String(describing: error), privacy: .public)")
            next = nil
        }
        guard let next else { return }
        let delay = max(1, next.timeIntervalSince(clock.now))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.pushPendingChanges()
        }
    }

    private func refreshPendingCount(store: TaskStore, userId: String) async {
        do {
            let count = try await store.pendingChangeCount(for: userId)
            update { $0.pendingCount = count }
        } catch {
            Log.sync.error("Counting pending changes failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Status

    private func update(_ change: (inout SyncStatus) -> Void) {
        var next = status
        change(&next)
        guard next != status else { return }
        status = next
        for continuation in statusSubscribers.values { continuation.yield(next) }
    }

    private func addSubscriber(_ id: UUID, _ continuation: AsyncStream<SyncStatus>.Continuation) {
        statusSubscribers[id] = continuation
        continuation.yield(status)
    }

    private func removeSubscriber(_ id: UUID) {
        statusSubscribers[id] = nil
    }
}
