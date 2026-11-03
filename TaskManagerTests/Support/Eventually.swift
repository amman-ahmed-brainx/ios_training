import Foundation
import Testing

/// Waits for asynchronous work (stream delivery, detached profile writes) to settle.
/// Polls instead of sleeping a fixed time, so passing tests finish as soon as they can.
/// Runs in the caller's isolation, so the condition can read main-actor state directly.
func eventually(
    timeout: Duration = .seconds(2),
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Condition not met within \(timeout)", sourceLocation: sourceLocation)
}
