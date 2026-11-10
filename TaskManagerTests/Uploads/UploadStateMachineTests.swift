import Foundation
import Testing
@testable import TaskManager

struct UploadStateMachineTests {
    @Test func happyPathQueuedToCompleted() {
        #expect(UploadStateMachine.next(from: .queued, on: .started) == .uploading)
        #expect(UploadStateMachine.next(from: .uploading, on: .finished(statusCode: 200)) == .completed)
    }

    @Test func httpErrorsAndTransportErrorsFail() {
        #expect(UploadStateMachine.next(from: .uploading, on: .finished(statusCode: 403)) == .failed)
        #expect(UploadStateMachine.next(from: .uploading, on: .transportError) == .failed)
        #expect(UploadStateMachine.next(from: .queued, on: .transportError) == .failed)
    }

    @Test func failedUploadsCanBeRetried() {
        #expect(UploadStateMachine.next(from: .failed, on: .retryRequested) == .queued)
        #expect(UploadStateMachine.next(from: .failed, on: .started) == .uploading)
    }

    @Test func staleCallbacksAfterCompletionAreIgnored() {
        #expect(UploadStateMachine.next(from: .completed, on: .transportError) == nil)
        #expect(UploadStateMachine.next(from: .completed, on: .finished(statusCode: 200)) == nil)
        #expect(UploadStateMachine.next(from: .queued, on: .finished(statusCode: 200)) == nil)
    }

    @Test func restRequestTargetsTheStorageEndpointWithTheIDToken() throws {
        let request = try BackgroundUploadManager.request(
            bucket: "demo.appspot.com", path: "attachments/t1/a1-big file.mov", contentType: "video/quicktime", idToken: "abc"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Firebase abc")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "video/quicktime")
        let url = try #require(request.url)
        #expect(url.host() == "firebasestorage.googleapis.com")
        #expect(url.path() == "/v0/b/demo.appspot.com/o")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "attachments/t1/a1-big file.mov")
    }

    @Test func parsesTheStoredSizeFromStoragesResponse() {
        #expect(BackgroundUploadManager.storedSize(from: Data(#"{"name":"x","size":"12345"}"#.utf8)) == 12_345)
        #expect(BackgroundUploadManager.storedSize(from: Data("garbage".utf8)) == nil)
    }
}
