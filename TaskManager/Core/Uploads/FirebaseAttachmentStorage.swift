import FirebaseStorage
import Foundation

/// `AttachmentStorage` backed by the Firebase Storage SDK (foreground only; large files go through
/// `BackgroundUploadManager`).
struct FirebaseAttachmentStorage: AttachmentStorage {
    func upload(data: Data, to path: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata) { value in
            guard let value, value.totalUnitCount > 0 else { return }
            progress(Double(value.completedUnitCount) / Double(value.totalUnitCount))
        }
    }

    func download(_ path: String, to localURL: URL) async throws -> URL {
        try await Storage.storage().reference(withPath: path).writeAsync(toFile: localURL)
    }

    func delete(_ path: String) async throws {
        try await Storage.storage().reference(withPath: path).delete()
    }
}
