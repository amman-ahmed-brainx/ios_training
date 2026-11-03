import Network

/// Reports connectivity changes. Each stream owns its own `NWPathMonitor` on a background queue.
struct NetworkMonitor: Sendable {
    func onlineUpdates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "com.brainxtech.taskmanager.network", qos: .utility))
        }
    }
}
