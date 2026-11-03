import Foundation

/// Source of "now". Injected so reminders, conflict resolution and backoff are testable.
/// Named `AppClock` to avoid shadowing the standard library's `Clock` protocol.
protocol AppClock: Sendable {
    var now: Date { get }
}

/// Wall-clock time.
struct SystemClock: AppClock {
    var now: Date { Date() }
}
