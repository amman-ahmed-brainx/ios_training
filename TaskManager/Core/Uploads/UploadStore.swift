import Foundation
import SwiftData

/// A Sendable view of an `UploadRecord`.
struct UploadSnapshot: Equatable, Sendable, Identifiable {
    let attachmentId: String
    let userId: String
    let taskId: String
    let fileName: String
    let contentType: String
    let size: Int64
    let localPath: String
    let storagePath: String
    let state: UploadState
    let lastError: String?

    var id: String { attachmentId }
}

/// Owns `UploadRecord` rows on a background executor (same container as `TaskStore`).
@ModelActor
actor UploadStore {
    static func make(container: ModelContainer) async -> UploadStore {
        await Task.detached(priority: .utility) { UploadStore(modelContainer: container) }.value
    }

    /// Creates the row here, on the store's executor (`@Model` objects never cross actors).
    func insert(_ snapshot: UploadSnapshot, createdAt: Date) throws {
        modelContext.insert(UploadRecord(
            attachmentId: snapshot.attachmentId, userId: snapshot.userId, taskId: snapshot.taskId,
            fileName: snapshot.fileName, contentType: snapshot.contentType, size: snapshot.size,
            localPath: snapshot.localPath, storagePath: snapshot.storagePath, createdAt: createdAt
        ))
        try modelContext.save()
    }

    func all() throws -> [UploadSnapshot] {
        try modelContext.fetch(FetchDescriptor<UploadRecord>(sortBy: [SortDescriptor(\.createdAt)])).map(\.snapshot)
    }

    func record(forSessionTask identifier: Int) throws -> UploadSnapshot? {
        try modelContext.fetch(FetchDescriptor<UploadRecord>(
            predicate: #Predicate { $0.sessionTaskIdentifier == identifier }
        )).first?.snapshot
    }

    /// Applies `event` through the state machine; ignores events that don't apply.
    @discardableResult
    func apply(_ event: UploadEvent, to attachmentId: String,
               sessionTaskIdentifier: Int? = nil, error: String? = nil) throws -> UploadState? {
        guard let record = try find(attachmentId),
              let current = UploadState(rawValue: record.stateRaw),
              let next = UploadStateMachine.next(from: current, on: event) else { return nil }
        record.stateRaw = next.rawValue
        if let sessionTaskIdentifier { record.sessionTaskIdentifier = sessionTaskIdentifier }
        record.lastError = error
        try modelContext.save()
        return next
    }

    func delete(_ attachmentId: String) throws {
        if let record = try find(attachmentId) {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func deleteAll() throws {
        try modelContext.delete(model: UploadRecord.self)
        try modelContext.save()
    }

    private func find(_ attachmentId: String) throws -> UploadRecord? {
        try modelContext.fetch(FetchDescriptor<UploadRecord>(predicate: #Predicate { $0.attachmentId == attachmentId })).first
    }
}

extension UploadRecord {
    var snapshot: UploadSnapshot {
        UploadSnapshot(attachmentId: attachmentId, userId: userId, taskId: taskId, fileName: fileName,
                       contentType: contentType, size: size, localPath: localPath, storagePath: storagePath,
                       state: UploadState(rawValue: stateRaw) ?? .failed, lastError: lastError)
    }
}
