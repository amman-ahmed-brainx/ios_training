import Foundation
import Testing
@testable import TaskManager

actor MockAttachmentStorage: AttachmentStorage {
    private(set) var uploadedPaths: [String] = []
    private(set) var deletedPaths: [String] = []
    private var failUploads = false

    func setFailUploads(_ fail: Bool) { failUploads = fail }

    func upload(data: Data, to path: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        if failUploads { throw URLError(.notConnectedToInternet) }
        uploadedPaths.append(path)
        progress(1)
    }

    func download(_ path: String, to localURL: URL) async throws -> URL { localURL }

    func delete(_ path: String) async throws { deletedPaths.append(path) }
}

struct MockCompressor: ImageCompressing {
    var fails = false
    func compressedJPEG(from data: Data, maxDimension: Int, quality: Double) async throws -> Data {
        if fails { throw ImageCompressionError.unreadableImage }
        return Data(repeating: 1, count: 10)
    }
}

@MainActor
struct AttachmentsViewModelTests {
    private let repository = MockTaskRepository()
    private let storage = MockAttachmentStorage()

    private func model(compressor: MockCompressor = MockCompressor()) -> AttachmentsViewModel {
        AttachmentsViewModel(taskId: "t1", userId: "uid-ada", repository: repository, storage: storage, compressor: compressor)
    }

    @Test func addedImageIsCompressedUploadedAndRecorded() async {
        let model = model()

        await model.addImage(Data(repeating: 0, count: 1000))

        let paths = await storage.uploadedPaths
        #expect(paths.count == 1)
        #expect(paths.first?.hasPrefix("attachments/t1/") == true)
        let calls = await repository.calls
        guard case .addAttachment(let attachment, "t1", "uid-ada")? = calls.first else {
            Issue.record("Expected addAttachment, got \(calls)")
            return
        }
        #expect(attachment.size == 10)
        #expect(attachment.contentType == "image/jpeg")
        #expect(model.uploads.isEmpty)
    }

    @Test func failedUploadCanBeRetried() async {
        await storage.setFailUploads(true)
        let model = model()

        await model.addImage(Data([1, 2, 3]))
        let failed = model.uploads.first
        #expect(failed?.state == .failed(String(localized: "Upload failed")))

        await storage.setFailUploads(false)
        if let failed { await model.retry(failed) }

        #expect(model.uploads.isEmpty)
        #expect(await storage.uploadedPaths.count == 1)
    }

    @Test func unreadableImageShowsAnError() async {
        let model = model(compressor: MockCompressor(fails: true))

        await model.addImage(Data([0]))

        #expect(model.errorMessage != nil)
        #expect(await storage.uploadedPaths.isEmpty)
    }

    @Test func deleteRemovesMetadataAndStoredBytes() async {
        let attachment = TaskAttachment(id: "a1", name: "x.pdf", storagePath: "attachments/t1/a1-x.pdf", size: 5, contentType: "application/pdf")

        await model().delete(attachment)

        #expect(await repository.calls == [.removeAttachment(id: "a1", taskId: "t1", userId: "uid-ada")])
        #expect(await storage.deletedPaths == ["attachments/t1/a1-x.pdf"])
    }

    @Test func importFailureIsReported() {
        let model = model()
        model.reportImportFailure()
        #expect(model.errorMessage != nil)
    }
}
