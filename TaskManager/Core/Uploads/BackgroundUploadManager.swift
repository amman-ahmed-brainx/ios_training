import FirebaseCore
import SwiftData
import Foundation
import os

/// A file to upload as an attachment of `taskId`.
struct UploadJob: Sendable {
    let fileURL: URL
    let taskId: String
    let attachmentId: String
    let fileName: String
    let contentType: String
    let userId: String
}

/// Large-file uploads, as the attachments screen uses them.
protocol UploadManaging: Sendable {
    /// Takes ownership of `job.fileURL` (moved into PendingUploads) and uploads it in the background.
    func enqueue(_ job: UploadJob) async throws
    /// Uploads for `taskId` that haven't completed yet, now and after every change.
    func uploads(for taskId: String) -> AsyncStream<[UploadSnapshot]>
    func retry(_ attachmentId: String) async
    /// Gives up on a failed upload and deletes its local copy.
    func discard(_ attachmentId: String) async
}

/// Starts uploads on some session and reports their task identifiers. Wrapped so the upload state
/// handling can be exercised without a real background `URLSession`.
protocol UploadTransport: Sendable {
    func startUpload(_ request: URLRequest, fromFile fileURL: URL) -> Int
    func cancelAll()
}

/// Events from the background session's delegate, delivered in order to the manager.
enum UploadSessionEvent: Sendable {
    case receivedData(taskIdentifier: Int, Data)
    case completed(taskIdentifier: Int, statusCode: Int?, errorDescription: String?)
    case finishedBackgroundEvents
}

/// The background `URLSession` and its delegate. The Firebase Storage SDK can't upload in the
/// background, so large files use the Storage REST endpoint with the user's ID token instead.
final class BackgroundURLSessionTransport: NSObject, UploadTransport, URLSessionDataDelegate, Sendable {
    static let identifier = "com.brainxtech.taskmanager.uploads"

    let events: AsyncStream<UploadSessionEvent>
    private let continuation: AsyncStream<UploadSessionEvent>.Continuation
    // Assigned once in init, before any other thread can see `self`; URLSession itself is Sendable.
    private nonisolated(unsafe) var session: URLSession?

    override init() {
        (events, continuation) = AsyncStream.makeStream(of: UploadSessionEvent.self)
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func startUpload(_ request: URLRequest, fromFile fileURL: URL) -> Int {
        guard let session else { return -1 }
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.resume()
        return task.taskIdentifier
    }

    func cancelAll() {
        session?.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        continuation.yield(.receivedData(taskIdentifier: dataTask.taskIdentifier, data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        continuation.yield(.completed(taskIdentifier: task.taskIdentifier, statusCode: status,
                                      errorDescription: error?.localizedDescription))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        continuation.yield(.finishedBackgroundEvents)
    }
}

/// Holds the completion handler iOS passes when it relaunches the app for background-session events.
@MainActor
final class BackgroundSessionEvents {
    private var completionHandler: (() -> Void)?

    func store(_ handler: @escaping () -> Void) {
        completionHandler = handler
    }

    /// Must be called on the main thread once all events are processed.
    func complete() {
        completionHandler?()
        completionHandler = nil
    }
}

/// Uploads large attachments with a background `URLSession`, persisting each upload in SwiftData so
/// it survives suspension, termination and relaunch.
actor BackgroundUploadManager: UploadManaging, SessionLifecycleObserver {
    private let storeTask: Task<UploadStore, Never>
    private let transport: any UploadTransport
    private let events: AsyncStream<UploadSessionEvent>
    private let auth: any AuthService
    private let repository: any TaskRepository
    private let bucket: String
    private let sessionEvents: BackgroundSessionEvents
    private var responseData: [Int: Data] = [:]
    private var eventLoop: Task<Void, Never>?
    private var subscribers: [UUID: (taskId: String, continuation: AsyncStream<[UploadSnapshot]>.Continuation)] = [:]

    private static var pendingDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "PendingUploads", directoryHint: .isDirectory)
    }

    /// The default Storage bucket from `GoogleService-Info.plist`, if Firebase is configured.
    static var configuredBucket: String? { FirebaseApp.app()?.options.storageBucket }

    init(container: ModelContainerHandle, auth: any AuthService, repository: any TaskRepository,
         bucket: String, sessionEvents: BackgroundSessionEvents) {
        storeTask = Task { await UploadStore.make(container: container.container) }
        let transport = BackgroundURLSessionTransport()
        self.transport = transport
        events = transport.events
        self.auth = auth
        self.repository = repository
        self.bucket = bucket
        self.sessionEvents = sessionEvents
    }

    /// Starts consuming session events. Called at launch so events for uploads started before a
    /// relaunch are handled.
    func activate() {
        guard eventLoop == nil else { return }
        let events = events
        eventLoop = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    // MARK: UploadManaging

    func enqueue(_ job: UploadJob) async throws {
        let directory = Self.pendingDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(job.attachmentId)-\(job.fileName)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: job.fileURL, to: destination)
        let size = (try? FileManager.default.attributesOfItem(atPath: destination.path())[.size] as? Int64) ?? 0
        let snapshot = UploadSnapshot(
            attachmentId: job.attachmentId, userId: job.userId, taskId: job.taskId, fileName: job.fileName,
            contentType: job.contentType, size: size, localPath: destination.path(),
            storagePath: TaskAttachment.storagePath(taskId: job.taskId, attachmentId: job.attachmentId, fileName: job.fileName),
            state: .queued, lastError: nil
        )
        let store = await storeTask.value
        try await store.insert(snapshot, createdAt: .now)
        await start(snapshot, store: store)
    }

    nonisolated func uploads(for taskId: String) -> AsyncStream<[UploadSnapshot]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [UploadSnapshot].self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in Task { await self?.removeSubscriber(id) } }
        Task { await self.addSubscriber(id, taskId: taskId, continuation: continuation) }
        return stream
    }

    func retry(_ attachmentId: String) async {
        let store = await storeTask.value
        guard (try? await store.apply(.retryRequested, to: attachmentId)) != nil,
              let snapshot = try? await store.all().first(where: { $0.attachmentId == attachmentId }) else { return }
        await start(snapshot, store: store)
    }

    func discard(_ attachmentId: String) async {
        let store = await storeTask.value
        if let snapshot = try? await store.all().first(where: { $0.attachmentId == attachmentId }) {
            try? FileManager.default.removeItem(atPath: snapshot.localPath)
        }
        try? await store.delete(attachmentId)
        await publish(store: store)
    }

    // MARK: Session lifecycle

    func sessionWillEnd(uid: String, reason: SignOutReason) async {
        // Pending work belongs to the signed-out user: stop it and remove the copies.
        transport.cancelAll()
        let store = await storeTask.value
        for snapshot in (try? await store.all()) ?? [] {
            try? FileManager.default.removeItem(atPath: snapshot.localPath)
        }
        try? await store.deleteAll()
        await publish(store: store)
    }

    // MARK: Uploading

    private func start(_ snapshot: UploadSnapshot, store: UploadStore) async {
        do {
            let token = try await auth.currentIDToken(forceRefresh: false)
            let request = try Self.request(bucket: bucket, path: snapshot.storagePath,
                                           contentType: snapshot.contentType, idToken: token)
            let identifier = transport.startUpload(request, fromFile: URL(filePath: snapshot.localPath))
            try await store.apply(.started, to: snapshot.attachmentId, sessionTaskIdentifier: identifier)
        } catch {
            _ = try? await store.apply(.transportError, to: snapshot.attachmentId, error: error.localizedDescription)
        }
        await publish(store: store)
    }

    /// `POST https://firebasestorage.googleapis.com/v0/b/<bucket>/o?name=<path>` with the user's ID token.
    static func request(bucket: String, path: String, contentType: String, idToken: String) throws -> URLRequest {
        var components = URLComponents()
        if FirebaseBootstrap.usesEmulators {
            components.scheme = "http"
            components.host = FirebaseBootstrap.emulatorHost
            components.port = 9199
        } else {
            components.scheme = "https"
            components.host = "firebasestorage.googleapis.com"
        }
        components.path = "/v0/b/\(bucket)/o"
        components.queryItems = [URLQueryItem(name: "name", value: path)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Firebase \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return request
    }

    private func handle(_ event: UploadSessionEvent) async {
        switch event {
        case .receivedData(let identifier, let data):
            responseData[identifier, default: Data()].append(data)
        case .completed(let identifier, let statusCode, let errorDescription):
            await complete(identifier: identifier, statusCode: statusCode, errorDescription: errorDescription)
        case .finishedBackgroundEvents:
            await sessionEvents.complete()
        }
    }

    private func complete(identifier: Int, statusCode: Int?, errorDescription: String?) async {
        let body = responseData.removeValue(forKey: identifier)
        let store = await storeTask.value
        guard let snapshot = try? await store.record(forSessionTask: identifier) else { return }
        let event: UploadEvent = statusCode.map { .finished(statusCode: $0) } ?? .transportError
        let state = try? await store.apply(event, to: snapshot.attachmentId, error: errorDescription)
        if state == .completed {
            await finish(snapshot, responseBody: body, store: store)
        } else {
            Log.uploads.error("Background upload failed: \(errorDescription ?? "HTTP \(statusCode ?? 0)", privacy: .public)")
        }
        await publish(store: store)
    }

    /// Records the stored file on the task and removes the local copy.
    private func finish(_ snapshot: UploadSnapshot, responseBody: Data?, store: UploadStore) async {
        let size = Self.storedSize(from: responseBody) ?? snapshot.size
        let attachment = TaskAttachment(id: snapshot.attachmentId, name: snapshot.fileName,
                                        storagePath: snapshot.storagePath, size: size, contentType: snapshot.contentType)
        do {
            try await repository.addAttachment(attachment, toTask: snapshot.taskId, by: snapshot.userId)
        } catch {
            Log.uploads.error("Recording an uploaded attachment failed: \(String(describing: error), privacy: .public)")
        }
        try? FileManager.default.removeItem(atPath: snapshot.localPath)
        try? await store.delete(snapshot.attachmentId)
    }

    /// Storage's JSON response reports the stored size as a string.
    static func storedSize(from body: Data?) -> Int64? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let size = json["size"] as? String else { return nil }
        return Int64(size)
    }

    // MARK: Observers

    private func publish(store: UploadStore) async {
        let open = ((try? await store.all()) ?? []).filter { $0.state != .completed }
        for subscriber in subscribers.values {
            subscriber.continuation.yield(open.filter { $0.taskId == subscriber.taskId })
        }
    }

    private func addSubscriber(_ id: UUID, taskId: String, continuation: AsyncStream<[UploadSnapshot]>.Continuation) async {
        subscribers[id] = (taskId, continuation)
        await publish(store: await storeTask.value)
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}

/// Lets a `ModelContainer` cross into the upload manager's initialiser.
struct ModelContainerHandle: Sendable {
    let container: ModelContainer
}
