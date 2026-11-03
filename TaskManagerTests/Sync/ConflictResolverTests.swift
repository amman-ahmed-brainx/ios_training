import Foundation
import Testing
@testable import TaskManager

struct ConflictResolverTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func versioned(title: String, status: TaskStatus, updatedAt: TimeInterval, statusAt: TimeInterval) -> VersionedTask {
        VersionedTask(
            item: .make(id: "t1", title: title, status: status, updatedAt: base.addingTimeInterval(updatedAt)),
            statusUpdatedAt: base.addingTimeInterval(statusAt)
        )
    }

    @Test func newerLocalEditWinsAndStillNeedsPush() {
        let outcome = ConflictResolver.resolve(
            local: versioned(title: "Local", status: .todo, updatedAt: 20, statusAt: 0),
            remote: versioned(title: "Remote", status: .todo, updatedAt: 10, statusAt: 0)
        )
        #expect(outcome.merged.item.title == "Local")
        #expect(outcome.needsPush)
    }

    @Test func remoteWinsTies() {
        let outcome = ConflictResolver.resolve(
            local: versioned(title: "Local", status: .todo, updatedAt: 10, statusAt: 0),
            remote: versioned(title: "Remote", status: .todo, updatedAt: 10, statusAt: 0)
        )
        #expect(outcome.merged.item.title == "Remote")
        #expect(!outcome.needsPush)
    }

    @Test func collaboratorsNewerStatusSurvivesOwnersStaleEdit() {
        // Owner edited the title offline at t=30 but last touched status at t=0;
        // the collaborator marked it done at t=20.
        let outcome = ConflictResolver.resolve(
            local: versioned(title: "Owner title", status: .todo, updatedAt: 30, statusAt: 0),
            remote: versioned(title: "Old title", status: .done, updatedAt: 20, statusAt: 20)
        )
        #expect(outcome.merged.item.title == "Owner title")
        #expect(outcome.merged.item.status == .done)
        #expect(outcome.needsPush)
    }

    @Test func mapperRoundTripsAndToleratesUnknownValues() throws {
        let original = versioned(title: "Round trip", status: .inProgress, updatedAt: 5, statusAt: 5)
        var fields = TaskDocumentMapper.fields(for: original)
        let decoded = try #require(TaskDocumentMapper.task(id: "t1", fields: fields))
        #expect(decoded.item.title == "Round trip")
        #expect(decoded.item.status == .inProgress)

        fields["status"] = "archived"
        fields["priority"] = 42
        let tolerant = try #require(TaskDocumentMapper.task(id: "t1", fields: fields))
        #expect(tolerant.item.status == .todo)
        #expect(tolerant.item.priority == .medium)
        #expect(TaskDocumentMapper.task(id: "t1", fields: ["title": "No owner"]) == nil)
    }
}
