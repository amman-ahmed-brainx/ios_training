import SwiftUI

/// Sheet for sharing a task with other people.
struct InviteCollaboratorView: View {
    @State private var model: InviteCollaboratorViewModel
    @State private var pendingRemoval: UserSummary?
    @Environment(\.dismiss) private var dismiss

    init(model: InviteCollaboratorViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormField("Email", text: $model.email, kind: .email, error: model.emailError, identifier: "invite.email")
                    PrimaryButton("Invite", isLoading: model.isInviting) { Task { await model.invite() } }
                        .accessibilityIdentifier("invite.submit")
                } footer: {
                    Text("Collaborators can see the task and change its status. Only you can edit or delete it.")
                }
                if let message = model.message {
                    switch message {
                    case .error(let text): MessageBanner(text, kind: .error)
                    case .invited(let text): MessageBanner(text, kind: .info)
                    }
                }
                Section("People") {
                    if model.collaborators.isEmpty {
                        Text("Not shared yet").foregroundStyle(Palette.secondaryText)
                    }
                    ForEach(model.collaborators) { person in
                        LabeledContent(person.label) { Text(verbatim: person.email) }
                            .swipeActions {
                                Button("Remove", role: .destructive) { pendingRemoval = person }
                            }
                            .accessibilityAction(named: Text("Remove")) { pendingRemoval = person }
                    }
                }
            }
            .navigationTitle("Share Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await model.loadCollaborators() }
            .confirmationDialog(
                "Stop sharing with this person?",
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                titleVisibility: .visible,
                presenting: pendingRemoval
            ) { person in
                Button("Remove \(person.label)", role: .destructive) { Task { await model.remove(person) } }
            }
        }
    }
}

#if DEBUG
#Preview("Shared, dark AX5") {
    InviteCollaboratorView(model: InviteCollaboratorViewModel(
        task: .preview(title: "Plan offsite"),
        userId: "uitest-user",
        repository: UnavailableTaskRepository(),
        directory: FakeUserDirectory()
    ))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility5)
}
#endif
