import Foundation

/// Cloud storage for attachment bytes at `attachments/{taskId}/{fileName}`.
protocol AttachmentStorage: Sendable {
    /// Foreground upload; reports progress from 0 to 1.
    func upload(data: Data, to path: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws
    /// Downloads to a local file (for preview) and returns its URL.
    func download(_ path: String, to localURL: URL) async throws -> URL
    func delete(_ path: String) async throws
}

extension TaskAttachment {
    static func storagePath(taskId: String, attachmentId: String, fileName: String) -> String {
        "attachments/\(taskId)/\(attachmentId)-\(fileName)"
    }

    var isImage: Bool { contentType.hasPrefix("image/") }
}
