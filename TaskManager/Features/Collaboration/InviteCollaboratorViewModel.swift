import Foundation
import Observation

/// Invite people to a task by email, and remove them again. Owner only.
@MainActor
@Observable
final class InviteCollaboratorViewModel {
    var email = ""
    private(set) var collaborators: [UserSummary] = []
    private(set) var isInviting = false
    private(set) var emailError: String?
    private(set) var message: Message?

    enum Message: Equatable {
        case error(String)
        case invited(String)
    }

    let taskId: String
    private let ownerId: String
    private var collaboratorIds: [String]
    private let repository: any TaskRepository
    private let directory: any UserDirectory

    init(task: TaskItem, userId: String, repository: any TaskRepository, directory: any UserDirectory) {
        taskId = task.id
        ownerId = userId
        collaboratorIds = task.collaboratorIds
        self.repository = repository
        self.directory = directory
    }

    /// Resolves collaborator ids to names for the list.
    func loadCollaborators() async {
        let directory = directory
        let ids = collaboratorIds
        let found = await withTaskGroup(of: (String, UserSummary?).self) { group in
            for id in ids {
                group.addTask { (id, try? await directory.user(withId: id)) }
            }
            var byId: [String: UserSummary] = [:]
            for await (id, summary) in group { byId[id] = summary }
            return byId
        }
        // Keep the task's order; unknown ids still get a row so they can be removed.
        collaborators = ids.map { found[$0] ?? UserSummary(id: $0, email: "", displayName: String(localized: "Unknown user")) }
    }

    func invite() async {
        guard !isInviting else { return }
        message = nil
        emailError = Validators.email(email)?.message
        if emailError != nil { return }
        isInviting = true
        defer { isInviting = false }
        do {
            guard let person = try await directory.user(withEmail: email) else {
                message = .error(String(localized: "No one with that email uses Tasks yet."))
                return
            }
            if person.id == ownerId {
                message = .error(String(localized: "You already own this task."))
                return
            }
            if collaboratorIds.contains(person.id) {
                message = .error(String(localized: "\(person.label) is already a collaborator."))
                return
            }
            try await repository.addCollaborator(person.id, toTask: taskId, by: ownerId)
            collaboratorIds.append(person.id)
            collaborators.append(person)
            email = ""
            message = .invited(String(localized: "\(person.label) can now see this task."))
        } catch let error as TaskRepositoryError {
            message = .error(error.message)
        } catch {
            message = .error(String(localized: "Couldn't look that person up. Check your connection."))
        }
    }

    func remove(_ person: UserSummary) async {
        do {
            try await repository.removeCollaborator(person.id, fromTask: taskId, by: ownerId)
            collaboratorIds.removeAll { $0 == person.id }
            collaborators.removeAll { $0.id == person.id }
        } catch {
            message = .error(error.message)
        }
    }
}
