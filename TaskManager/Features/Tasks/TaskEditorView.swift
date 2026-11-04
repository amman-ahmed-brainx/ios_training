import SwiftUI

/// Sheet for creating a task or editing one.
struct TaskEditorView: View {
    @State private var model: TaskEditorViewModel
    @State private var isConfirmingDiscard = false
    @FocusState private var isTitleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: TaskEditorViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.errorMessage {
                    Section { MessageBanner(error, kind: .error) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Title", text: $model.title, axis: .vertical)
                        .font(.headline)
                        .focused($isTitleFocused)
                        .submitLabel(.next)
                        .accessibilityIdentifier("taskEditor.title")
                    if let error = model.titleError {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                    TextField("Notes", text: $model.notes, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("taskEditor.notes")
                } footer: {
                    if !model.canEditDetails {
                        Text("Only the owner can change the title, notes, priority and due date.")
                    }
                }
                .disabled(!model.canEditDetails)

                Section {
                    Picker("Status", selection: $model.status) {
                        ForEach(TaskStatus.allCases, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    .accessibilityIdentifier("taskEditor.status")
                    Picker("Priority", selection: $model.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    .disabled(!model.canEditDetails)
                }

                Section {
                    Toggle("Due Date", isOn: $model.hasDueDate)
                        .accessibilityIdentifier("taskEditor.hasDueDate")
                    if model.hasDueDate {
                        DatePicker("Due", selection: $model.dueDateSelection)
                            .accessibilityIdentifier("taskEditor.dueDate")
                    }
                }
                .disabled(!model.canEditDetails)
            }
            .navigationTitle(model.isCreating ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if model.isDirty { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("taskEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("taskEditor.save")
                }
            }
            .interactiveDismissDisabled(model.isDirty)
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .onChange(of: isTitleFocused) { wasFocused, _ in
                if wasFocused { model.didEndEditing(.title) }
            }
            .onAppear {
                if model.isCreating { isTitleFocused = true }
            }
        }
    }

    private func save() {
        isTitleFocused = false
        Task {
            if await model.save() { dismiss() }
        }
    }
}
