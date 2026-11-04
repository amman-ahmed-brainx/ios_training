import Foundation

/// JSON export and import of tasks. Pure and synchronous, so callers run it off the main thread.
enum TaskTransfer {
    struct Archive: Codable, Equatable, Sendable {
        var version = 1
        var exportedAt: Date
        var tasks: [TaskItem]
    }

    static func encode(_ tasks: [TaskItem], exportedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Archive(exportedAt: exportedAt, tasks: tasks))
    }

    /// The editable fields of each task in an export, ready to be created as new tasks.
    static func drafts(from data: Data) throws -> [TaskDraft] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Archive.self, from: data).tasks.map(TaskDraft.init)
    }
}
