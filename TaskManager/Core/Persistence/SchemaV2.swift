import Foundation
import SwiftData

/// Adds `UploadRecord` for background uploads. `TaskEntity` is unchanged, so V1 → V2 is a
/// lightweight migration (a new entity only).
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [SchemaV1.TaskEntity.self, UploadRecord.self] }

    /// One large file being uploaded by the background `URLSession`. Persisted so an upload
    /// survives the app being suspended, terminated or relaunched by the system.
    @Model
    final class UploadRecord {
        @Attribute(.unique) var attachmentId: String
        var userId: String
        var taskId: String
        var fileName: String
        var contentType: String
        var size: Int64
        /// Copy inside Application Support/PendingUploads; background sessions upload from files.
        var localPath: String
        var storagePath: String
        /// `URLSessionTask.taskIdentifier`, to match delegate callbacks after a relaunch.
        var sessionTaskIdentifier: Int?
        var stateRaw: String
        var lastError: String?
        var createdAt: Date

        init(attachmentId: String, userId: String, taskId: String, fileName: String, contentType: String,
             size: Int64, localPath: String, storagePath: String, createdAt: Date) {
            self.attachmentId = attachmentId
            self.userId = userId
            self.taskId = taskId
            self.fileName = fileName
            self.contentType = contentType
            self.size = size
            self.localPath = localPath
            self.storagePath = storagePath
            sessionTaskIdentifier = nil
            stateRaw = UploadState.queued.rawValue
            lastError = nil
            self.createdAt = createdAt
        }
    }
}

typealias UploadRecord = SchemaV2.UploadRecord
