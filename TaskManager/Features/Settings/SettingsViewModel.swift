import Foundation
import Observation

/// Settings: account, sync and sign-out.
@MainActor
@Observable
final class SettingsViewModel {
    let session: AuthSession
    private(set) var isSigningOut = false
    private(set) var syncStatus = SyncStatus.idle
    private let sessionController: SessionController
    private let sync: (any SyncControlling)?
    private let reminderCoordinator: ReminderCoordinator?
    private let preferences = ReminderPreferences()
    private let repository: (any TaskRepository)?

    /// Export/import progress from 0 to 1, or `nil` when idle.
    private(set) var transferProgress: Double?
    private(set) var transferMessage: String?
    /// The written export, ready to share.
    private(set) var exportURL: URL?

    var leadTime: ReminderLeadTime {
        didSet {
            preferences.leadTime = leadTime
            Task { [reminderCoordinator] in await reminderCoordinator?.refresh() }
        }
    }

    init(
        session: AuthSession,
        sessionController: SessionController,
        sync: (any SyncControlling)? = nil,
        reminderCoordinator: ReminderCoordinator? = nil,
        repository: (any TaskRepository)? = nil
    ) {
        self.session = session
        self.sessionController = sessionController
        self.sync = sync
        self.reminderCoordinator = reminderCoordinator
        self.repository = repository
        leadTime = ReminderPreferences().leadTime
    }

    var isSyncAvailable: Bool { sync != nil }

    func observeSync() async {
        guard let sync else { return }
        for await status in sync.statusUpdates() {
            syncStatus = status
        }
    }

    func syncNow() async {
        await sync?.syncNow()
    }

    /// Writes the user's tasks to a JSON file (encoding and file I/O off the main thread).
    func exportTasks() async {
        guard let repository, transferProgress == nil else { return }
        transferProgress = 0
        defer { transferProgress = nil }
        var updates = repository.observeTasks(for: session.uid).makeAsyncIterator()
        let tasks = await updates.next() ?? []
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                let data = try TaskTransfer.encode(tasks, exportedAt: .now)
                let url = FileManager.default.temporaryDirectory.appending(path: "Tasks.json")
                try data.write(to: url, options: .atomic)
                return url
            }.value
            exportURL = url
            transferMessage = String(localized: "Exported \(tasks.count) tasks.")
        } catch {
            transferMessage = String(localized: "The export couldn't be written.")
        }
    }

    /// Creates a new task for each task in the file; reading and decoding run off the main thread.
    func importTasks(from url: URL) async {
        guard let repository, transferProgress == nil else { return }
        transferProgress = 0
        defer { transferProgress = nil }
        let drafts: [TaskDraft]
        do {
            drafts = try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try TaskTransfer.drafts(from: Data(contentsOf: url))
            }.value
        } catch {
            transferMessage = String(localized: "That file isn't a valid task export.")
            return
        }
        // One bad entry (e.g. an empty title) is skipped and counted rather than aborting the rest.
        var imported = 0
        for (index, draft) in drafts.enumerated() {
            if (try? await repository.create(draft, ownerId: session.uid)) != nil { imported += 1 }
            transferProgress = Double(index + 1) / Double(max(drafts.count, 1))
        }
        let skipped = drafts.count - imported
        transferMessage = skipped == 0
            ? String(localized: "Imported \(imported) tasks.")
            : String(localized: "Imported \(imported) tasks; skipped \(skipped) that couldn't be added.")
    }

    /// The system file picker failed to hand over a file.
    func reportImportPickerFailure() {
        transferMessage = String(localized: "That file couldn't be opened.")
    }

    func dismissTransferMessage() {
        transferMessage = nil
    }

    #if DEBUG
    /// Instruments helper: fills the list with 1,000 tasks to profile scrolling and sync.
    func generateSampleTasks(count: Int = 1000) async {
        guard let repository else { return }
        transferProgress = 0
        defer { transferProgress = nil }
        let priorities = TaskPriority.allCases
        for index in 0..<count {
            let draft = TaskDraft(
                title: "Sample task \(index + 1)",
                notes: "Generated for performance testing.",
                status: index.isMultiple(of: 5) ? .done : .todo,
                priority: priorities[index % priorities.count],
                dueDate: Date.now.addingTimeInterval(Double(index - 200) * 3600)
            )
            _ = try? await repository.create(draft, ownerId: session.uid)
            if index.isMultiple(of: 50) { transferProgress = Double(index) / Double(count) }
        }
    }
    #endif

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await sessionController.signOut()
    }
}
