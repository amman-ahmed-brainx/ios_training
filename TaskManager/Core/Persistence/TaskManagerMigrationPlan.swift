import Foundation
import SwiftData

/// Every shipped schema version, oldest first. To change the model: copy `SchemaV1` to `SchemaV2`,
/// edit the copy, point `TaskEntity` at it, append it here and add a `.lightweight` or `.custom` stage.
enum TaskManagerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)] }
}

/// Builds the app's `ModelContainer`.
enum PersistenceContainer {
    /// - Parameters:
    ///   - inMemory: `true` for previews, tests and `-uitest` runs.
    ///   - url: on-disk location; defaults to the app's Application Support store.
    static func make(inMemory: Bool, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = if let url {
            ModelConfiguration(schema: schema, url: url)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: TaskManagerMigrationPlan.self,
            configurations: configuration
        )
    }
}
