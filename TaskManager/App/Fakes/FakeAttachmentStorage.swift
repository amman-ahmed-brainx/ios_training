#if DEBUG
import Foundation

/// Stores attachment bytes in a temporary directory for previews and UI tests.
struct FakeAttachmentStorage: AttachmentStorage {
    private var root: URL { FileManager.default.temporaryDirectory.appending(path: "FakeStorage") }

    func upload(data: Data, to path: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        progress(1)
    }

    func download(_ path: String, to localURL: URL) async throws -> URL {
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.copyItem(at: root.appending(path: path), to: localURL)
        return localURL
    }

    func delete(_ path: String) async throws {
        try? FileManager.default.removeItem(at: root.appending(path: path))
    }
}
#endif
