import Foundation
import SwiftData
import Testing
@testable import TaskManager

/// Runs against a real SwiftData container (in memory unless noted), so the outbox fields,
/// predicates and saves are exercised exactly as in the app.
struct TaskStoreTests {
    private let clock = TestClock()

    private func makeStore() async throws -> TaskStore {
        await TaskStore.make(container: try PersistenceContainer.make(inMemory: true), clock: clock)
    }

    @Test func createRecordsAPendingCreate() async throws {
        let store = try await makeStore()

        let task = try await store.create(.titled("  Write report  ", priority: .high), ownerId: "uid-ada")

        #expect(task.title == "Write report")
        #expect(task.syncState == .pendingCreate)
        #expect(task.ownerId == "uid-ada")
        #expect(task.memberIds == ["uid-ada"])
        #expect(task.createdAt == clock.now)
        #expect(try await store.tasks(for: "uid-ada") == [task])
    }

    @Test(arguments: ["", "   ", String(repeating: "x", count: TaskStore.maxTitleLength + 1)])
    func createRejectsInvalidTitles(_ title: String) async throws {
        let store = try await makeStore()
        await #expect(throws: TaskRepositoryError.invalidTitle) {
            try await store.create(.titled(title), ownerId: "uid-ada")
        }
    }

    @Test func editingAnUnpushedTaskKeepsItACreate() async throws {
        let store = try await makeStore()
        let task = try await store.create(.titled("Draft"), ownerId: "uid-ada")
        clock.advance(by: 60)

        try await store.update(taskId: task.id, with: .titled("Final", priority: .low), by: "uid-ada")

        let updated = try #require(try await store.tasks(for: "uid-ada").first)
        #expect(updated.title == "Final")
        #expect(updated.priority == .low)
        #expect(updated.syncState == .pendingCreate)
        #expect(updated.updatedAt == clock.now)
    }

    @Test func setStatusChangesStatusAndTimestamp() async throws {
        let store = try await makeStore()
        let task = try await store.create(.titled("Ship it"), ownerId: "uid-ada")
        clock.advance(by: 30)

        try await store.setStatus(.done, taskId: task.id, by: "uid-ada")

        let updated = try #require(try await store.tasks(for: "uid-ada").first)
        #expect(updated.status == .done)
        #expect(updated.updatedAt == clock.now)
        #expect(updated.updatedBy == "uid-ada")
    }

    @Test func settingTheSameStatusIsANoOp() async throws {
        let store = try await makeStore()
        let task = try await store.create(.titled("Ship it"), ownerId: "uid-ada")
        clock.advance(by: 30)

        try await store.setStatus(.todo, taskId: task.id, by: "uid-ada")

        #expect(try await store.tasks(for: "uid-ada").first?.updatedAt == task.updatedAt)
    }

    @Test func deletingAnUnpushedTaskRemovesItOutright() async throws {
        let store = try await makeStore()
        let task = try await store.create(.titled("Oops"), ownerId: "uid-ada")

        try await store.delete(taskId: task.id, by: "uid-ada")

        #expect(try await store.tasks(for: "uid-ada").isEmpty)
        // No tombstone: there is nothing to delete on the backend.
        #expect(try await store.pendingChangeCount(for: "uid-ada") == 0)
    }

    @Test func otherUsersCannotSeeOrChangeTheTask() async throws {
        let store = try await makeStore()
        let task = try await store.create(.titled("Private"), ownerId: "uid-ada")

        #expect(try await store.tasks(for: "uid-grace").isEmpty)
        await #expect(throws: TaskRepositoryError.notFound) {
            try await store.setStatus(.done, taskId: task.id, by: "uid-grace")
        }
        await #expect(throws: TaskRepositoryError.notFound) {
            try await store.delete(taskId: task.id, by: "uid-grace")
        }
    }

    @Test func missingTaskReportsNotFound() async throws {
        let store = try await makeStore()
        await #expect(throws: TaskRepositoryError.notFound) {
            try await store.update(taskId: "nope", with: .titled("X"), by: "uid-ada")
        }
    }

    @Test func pendingChangeCountTracksTheOutbox() async throws {
        let store = try await makeStore()
        _ = try await store.create(.titled("One"), ownerId: "uid-ada")
        _ = try await store.create(.titled("Two"), ownerId: "uid-ada")
        _ = try await store.create(.titled("Other user"), ownerId: "uid-grace")

        #expect(try await store.pendingChangeCount(for: "uid-ada") == 2)
    }

    @Test func observersGetTheCurrentSnapshotAndEveryChange() async throws {
        let store = try await makeStore()
        _ = try await store.create(.titled("Existing"), ownerId: "uid-ada")
        var iterator = store.observeTasks(for: "uid-ada").makeAsyncIterator()

        #expect(await iterator.next()?.map(\.title) == ["Existing"])

        clock.advance(by: 1)
        _ = try await store.create(.titled("New"), ownerId: "uid-ada")
        #expect(await iterator.next()?.map(\.title) == ["New", "Existing"])
    }

    @Test func wipingTheCacheRemovesEveryUsersRowsAndNotifiesObservers() async throws {
        let store = try await makeStore()
        _ = try await store.create(.titled("Ada's"), ownerId: "uid-ada")
        _ = try await store.create(.titled("Grace's"), ownerId: "uid-grace")
        var iterator = store.observeTasks(for: "uid-ada").makeAsyncIterator()
        _ = await iterator.next()

        try await store.deleteAllLocalData()

        #expect(await iterator.next() == [])
        #expect(try await store.tasks(for: "uid-ada").isEmpty)
        #expect(try await store.tasks(for: "uid-grace").isEmpty)
    }

    @Test func pendingChangesSurviveARelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "relaunch-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let store = await TaskStore.make(container: try PersistenceContainer.make(inMemory: false, url: url), clock: clock)
            _ = try await store.create(.titled("Survives"), ownerId: "uid-ada")
        }

        // A new container on the same file, as after the app was killed and relaunched.
        let relaunched = await TaskStore.make(container: try PersistenceContainer.make(inMemory: false, url: url), clock: clock)
        let tasks = try await relaunched.tasks(for: "uid-ada")
        #expect(tasks.map(\.title) == ["Survives"])
        #expect(tasks.first?.syncState == .pendingCreate)
    }

    @Test func storeWorkRunsOffTheMainThread() async throws {
        let store = try await makeStore()
        #expect(await store.isRunningOnMainThread() == false)
    }
}

extension TaskStore {
    /// Test probe: where the actor's executor actually runs.
    func isRunningOnMainThread() -> Bool { Thread.isMainThread }
}
