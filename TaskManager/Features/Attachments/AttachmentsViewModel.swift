import Foundation
import Observation
import UniformTypeIdentifiers

/// Adds, uploads, previews and deletes a task's attachments.
/// Images are compressed on `ImageCompressor`'s actor and files are read off the main thread.
@MainActor
@Observable
final class AttachmentsViewModel {
    /// An attachment that is uploading or failed to upload (uploaded ones live on the task).
    struct Upload: Identifiable, Equatable {
        enum State: Equatable {
            case uploading(Double)
            case failed(String)
        }

        let id: String
        let name: String
        let size: Int64
        let isImage: Bool
        var state: State
    }

    private(set) var uploads: [Upload] = []
    private(set) var errorMessage: String?
    /// Set to a local file to open QuickLook.
    var previewURL: URL?

    let taskId: String
    private let userId: String
    private let repository: any TaskRepository
    private let storage: any AttachmentStorage
    private let compressor: any ImageCompressing
    private let uploader: (any UploadManaging)?
    /// Large files uploading in the background (survive leaving the app).
    private(set) var backgroundUploads: [UploadSnapshot] = []

    /// Above this, files go through the background `URLSession` instead of the Storage SDK.
    static let foregroundUploadLimit = 2 * 1024 * 1024
    /// Mirrors `allowedUpload()` in `firebase/storage.rules`; anything else would be rejected there.
    static func isUploadable(_ contentType: String) -> Bool {
        let prefixes = ["image/", "video/", "text/"]
        let applicationTypes: Set = ["application/pdf", "application/zip", "application/json", "application/rtf",
                                     "application/msword", "application/vnd.ms-excel", "application/vnd.ms-powerpoint"]
        return prefixes.contains { contentType.hasPrefix($0) }
            || applicationTypes.contains(contentType)
            || contentType.hasPrefix("application/vnd.openxmlformats-officedocument.")
    }

    /// Bytes kept for failed uploads so Retry doesn't need the original again.
    private var payloads: [String: (data: Data, contentType: String)] = [:]

    init(taskId: String, userId: String, repository: any TaskRepository,
         storage: any AttachmentStorage, compressor: any ImageCompressing, uploader: (any UploadManaging)? = nil) {
        self.taskId = taskId
        self.userId = userId
        self.repository = repository
        self.storage = storage
        self.compressor = compressor
        self.uploader = uploader
    }

    /// Follows background uploads for this task until cancelled (the view's `.task`).
    func observeBackgroundUploads() async {
        guard let uploader else { return }
        for await uploads in uploader.uploads(for: taskId) {
            backgroundUploads = uploads
        }
    }

    func retryBackground(_ upload: UploadSnapshot) async {
        await uploader?.retry(upload.attachmentId)
    }

    func discardBackground(_ upload: UploadSnapshot) async {
        await uploader?.discard(upload.attachmentId)
    }

    /// From PhotosPicker: compress, then upload.
    func addImage(_ data: Data) async {
        do {
            let jpeg = try await compressor.compressedJPEG(from: data, maxDimension: 2048, quality: 0.7)
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            await upload(jpeg, name: "Photo \(stamp).jpg", contentType: UTType.jpeg.preferredMIMEType ?? "image/jpeg")
        } catch {
            errorMessage = String(localized: "That photo couldn't be read.")
        }
    }

    /// From fileImporter: copy out of the security-scoped URL off the main thread, then upload.
    func addFile(at url: URL) async {
        guard let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
              Self.isUploadable(contentType) else {
            errorMessage = String(localized: "This type of file can't be attached.")
            return
        }
        if let uploader, let copy = await copyIfLarge(url) {
            do {
                try await uploader.enqueue(UploadJob(
                    fileURL: copy, taskId: taskId, attachmentId: UUID().uuidString, fileName: url.lastPathComponent,
                    contentType: contentType, userId: userId
                ))
            } catch {
                errorMessage = String(localized: "That file couldn't be prepared for upload.")
            }
            return
        }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }.value
            await upload(data, name: url.lastPathComponent, contentType: contentType)
        } catch {
            errorMessage = String(localized: "That file couldn't be opened.")
        }
    }

    func retry(_ upload: Upload) async {
        guard let payload = payloads[upload.id] else { return }
        uploads.removeAll { $0.id == upload.id }
        await self.upload(payload.data, name: upload.name, contentType: payload.contentType, id: upload.id)
    }

    func discard(_ upload: Upload) {
        uploads.removeAll { $0.id == upload.id }
        payloads[upload.id] = nil
    }

    func delete(_ attachment: TaskAttachment) async {
        do {
            try await repository.removeAttachment(id: attachment.id, fromTask: taskId, by: userId)
            try await storage.delete(attachment.storagePath)
        } catch let error as TaskRepositoryError {
            errorMessage = error.message
        } catch {
            // Metadata is gone and nothing references the file any more, so it stays orphaned in
            // Storage (only task members could ever read it). Known limitation, see README.
            Log.uploads.notice("Deleting stored bytes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func preview(_ attachment: TaskAttachment) async {
        let destination = FileManager.default.temporaryDirectory.appending(path: "\(attachment.id)-\(attachment.name)")
        do {
            previewURL = try await storage.download(attachment.storagePath, to: destination)
        } catch {
            errorMessage = String(localized: "The attachment couldn't be downloaded.")
        }
    }

    /// Copies a large file out of its security scope (off the main thread) for the background
    /// uploader; returns `nil` for small files, which upload in the foreground.
    private func copyIfLarge(_ url: URL) async -> URL? {
        let limit = Self.foregroundUploadLimit
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > limit else { return nil }
            let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
            return (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? copy : nil
        }.value
    }

    /// The system file picker failed to hand over a file.
    func reportImportFailure() {
        errorMessage = String(localized: "That file couldn't be opened.")
    }

    func dismissError() {
        errorMessage = nil
    }

    private func upload(_ data: Data, name: String, contentType: String, id: String = UUID().uuidString) async {
        let path = TaskAttachment.storagePath(taskId: taskId, attachmentId: id, fileName: name)
        payloads[id] = (data, contentType)
        uploads.append(Upload(id: id, name: name, size: Int64(data.count),
                              isImage: contentType.hasPrefix("image/"), state: .uploading(0)))
        do {
            try await storage.upload(data: data, to: path, contentType: contentType) { [weak self] fraction in
                Task { @MainActor in self?.setProgress(fraction, for: id) }
            }
            let attachment = TaskAttachment(id: id, name: name, storagePath: path, size: Int64(data.count), contentType: contentType)
            try await repository.addAttachment(attachment, toTask: taskId, by: userId)
            uploads.removeAll { $0.id == id }
            payloads[id] = nil
        } catch {
            setState(.failed(String(localized: "Upload failed")), for: id)
        }
    }

    private func setProgress(_ fraction: Double, for id: String) {
        guard let index = uploads.firstIndex(where: { $0.id == id }), case .uploading = uploads[index].state else { return }
        uploads[index].state = .uploading(fraction)
    }

    private func setState(_ state: Upload.State, for id: String) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].state = state
    }
}
