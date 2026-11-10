import OSLog

/// Unified logging categories, filterable in Console.app by subsystem.
enum Log {
    private static let subsystem = "com.brainxtech.taskmanager"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let uploads = Logger(subsystem: subsystem, category: "uploads")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
