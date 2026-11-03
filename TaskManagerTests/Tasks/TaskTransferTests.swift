import Foundation
import Testing
@testable import TaskManager

struct TaskTransferTests {
    @Test func exportRoundTripsTheEditableFields() throws {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = [TaskItem.make(title: "Report", status: .inProgress, priority: .high, dueDate: due)]

        let drafts = try TaskTransfer.drafts(from: TaskTransfer.encode(tasks, exportedAt: due))

        #expect(drafts == [TaskDraft(title: "Report", notes: "", status: .inProgress, priority: .high, dueDate: due)])
    }

    @Test func rejectsNonExportFiles() {
        #expect(throws: (any Error).self) { try TaskTransfer.drafts(from: Data("{}".utf8)) }
    }
}

@MainActor
struct SettingsTransferTests {
    @Test func importCreatesATaskPerEntry() async throws {
        let repository = MockTaskRepository()
        let session = AuthSession.ada
        let model = SettingsViewModel(
            session: session,
            sessionController: SessionController(auth: MockAuthService(), profiles: MockUserProfileStore()),
            repository: repository
        )
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try TaskTransfer.encode([.make(title: "A"), .make(title: "B")], exportedAt: .now).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await model.importTasks(from: url)

        #expect(await repository.calls.count == 2)
        #expect(model.transferProgress == nil)
        #expect(model.transferMessage == String(localized: "Imported 2 tasks."))
    }

    @Test func unreadableFileReportsAnInvalidExport() async {
        let model = SettingsViewModel(
            session: .ada,
            sessionController: SessionController(auth: MockAuthService(), profiles: MockUserProfileStore()),
            repository: MockTaskRepository()
        )
        await model.importTasks(from: URL(filePath: "/nonexistent/tasks.json"))
        #expect(model.transferMessage == String(localized: "That file isn't a valid task export."))
    }
}
