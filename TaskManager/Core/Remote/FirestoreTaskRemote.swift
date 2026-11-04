import FirebaseFirestore
import Foundation

/// `TaskRemote` backed by the `tasks` collection. Snapshot callbacks arrive on the background queue
/// configured in `FirebaseBootstrap`, so documents are parsed off the main thread.
struct FirestoreTaskRemote: TaskRemote {
    private var collection: CollectionReference { Firestore.firestore().collection("tasks") }

    func taskSnapshots(for userId: String) -> AsyncStream<RemoteTaskSnapshot> {
        AsyncStream { continuation in
            let registration = collection
                .whereField("memberIds", arrayContains: userId)
                .addSnapshotListener { snapshot, error in
                    guard let snapshot else {
                        Log.sync.error("Task listener failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                        return
                    }
                    let tasks = snapshot.documents.compactMap { document in
                        TaskDocumentMapper.task(id: document.documentID, fields: Self.plainValues(document.data()))
                    }
                    continuation.yield(RemoteTaskSnapshot(tasks: tasks, isFromCache: snapshot.metadata.isFromCache))
                }
            // ListenerRegistration isn't Sendable, but `remove()` is thread-safe and only called once here.
            nonisolated(unsafe) let listener = registration
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    func save(_ task: VersionedTask) async throws(RemoteError) {
        do {
            try await collection.document(task.item.id).setData(TaskDocumentMapper.fields(for: task))
        } catch {
            throw Self.map(error)
        }
    }

    func saveStatus(of task: VersionedTask) async throws(RemoteError) {
        do {
            try await collection.document(task.item.id).updateData(TaskDocumentMapper.statusFields(for: task))
        } catch {
            throw Self.map(error)
        }
    }

    func delete(taskId: String) async throws(RemoteError) {
        do {
            try await collection.document(taskId).delete()
        } catch {
            throw Self.map(error)
        }
    }

    /// Firestore returns `Timestamp`s; the mapper works with plain `Date`s.
    private static func plainValues(_ fields: [String: Any]) -> [String: Any] {
        fields.mapValues(plainValue)
    }

    private static func plainValue(_ value: Any) -> Any {
        switch value {
        case let timestamp as Timestamp: timestamp.dateValue()
        case let array as [Any]: array.map(plainValue)
        case let map as [String: Any]: map.mapValues(plainValue)
        default: value
        }
    }

    private static func map(_ error: any Error) -> RemoteError {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain, let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown
        }
        switch code {
        case .permissionDenied: return .permissionDenied
        case .notFound: return .notFound
        case .unauthenticated: return .unauthenticated
        case .unavailable, .deadlineExceeded, .resourceExhausted, .aborted, .internal: return .unavailable
        default: return .unknown
        }
    }
}
