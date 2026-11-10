/// Lifecycle of a background upload. Kept as a pure state machine so it is unit-testable
/// without a real `URLSession`.
enum UploadState: String, Codable, Sendable {
    case queued
    case uploading
    case completed
    case failed
}

enum UploadEvent: Equatable, Sendable {
    case started
    /// HTTP response from Storage (2xx means stored).
    case finished(statusCode: Int)
    case transportError
    case retryRequested
}

enum UploadStateMachine {
    /// The next state, or `nil` if the event doesn't apply (e.g. a stale callback after completion).
    static func next(from state: UploadState, on event: UploadEvent) -> UploadState? {
        switch (state, event) {
        case (.queued, .started), (.failed, .started):
            .uploading
        case (.uploading, .finished(let code)):
            (200..<300).contains(code) ? .completed : .failed
        case (.uploading, .transportError), (.queued, .transportError):
            .failed
        case (.failed, .retryRequested):
            .queued
        default:
            nil
        }
    }
}
