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
    /// Bytes kept for failed uploads so Retry doesn't need the original again.
    private var payloads: [String: (data: Data, contentType: String)] = [:]

    init(taskId: String, userId: String, repository: any TaskRepository,
         storage: any AttachmentStorage, compressor: any ImageCompressing) {
        self.taskId = taskId
        self.userId = userId
        self.repository = repository
        self.storage = storage
        self.compressor = compressor
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
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }.value
            let type = UTType(filenameExtension: url.pathExtension)
            await upload(data, name: url.lastPathComponent, contentType: type?.preferredMIMEType ?? "application/octet-stream")
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
            // Metadata is gone; an orphaned file is cleaned up with the task.
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
