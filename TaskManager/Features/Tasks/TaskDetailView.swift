import SwiftUI

/// Read view of one task with quick status changes; owners can edit and delete.
struct TaskDetailView: View {
    @State private var model: TaskDetailViewModel
    @State private var attachments: AttachmentsViewModel?
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    private let onEdit: (TaskItem) -> Void

    init(model: TaskDetailViewModel, attachments: AttachmentsViewModel?, onEdit: @escaping (TaskItem) -> Void) {
        _model = State(initialValue: model)
        _attachments = State(initialValue: attachments)
        self.onEdit = onEdit
    }

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.observe() }
            .confirmationDialog("Delete this task?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await model.delete() { dismiss() }
                    }
                }
            } message: {
                Text("It will be deleted for everyone it's shared with.")
            }
            .alert("Couldn't Update Task", isPresented: isShowingError) {
                Button("OK", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.actionError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .missing:
            EmptyStateView(systemImage: "trash", title: "Task Deleted", message: "This task is no longer available.")
        case .failed(let message):
            ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded(let task):
            details(for: task)
                .toolbar { toolbar(for: task) }
        }
    }

    private func details(for task: TaskItem) -> some View {
        List {
            headerSection(for: task)
            statusSection(for: task)
            detailsSection(for: task)
            if let attachments {
                AttachmentsSection(model: attachments, attachments: task.attachments, canEdit: model.canEditDetails)
            }
            historySection(for: task)
        }
    }

    private func headerSection(for task: TaskItem) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(task.title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("taskDetail.title")
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.body)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func statusSection(for task: TaskItem) -> some View {
        Section("Status") {
            Picker("Status", selection: statusBinding(for: task)) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Label(status.title, systemImage: status.systemImage).tag(status)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(!model.canChangeStatus)
            .accessibilityIdentifier("taskDetail.status")
        }
    }

    private func detailsSection(for task: TaskItem) -> some View {
        Section("Details") {
            LabeledContent("Priority") { PriorityBadge(priority: task.priority) }
            LabeledContent("Due") {
                if let dueDate = task.dueDate {
                    VStack(alignment: .trailing) {
                        Text(dueDate, format: .dateTime.weekday().day().month().hour().minute())
                        if model.isOverdue {
                            Label("Overdue", systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                } else {
                    Text("No due date")
                }
            }
            if !task.collaboratorIds.isEmpty {
                LabeledContent("Shared with") {
                    Text("\(task.collaboratorIds.count) people")
                }
            }
        }
    }

    private func historySection(for task: TaskItem) -> some View {
        Section {
            LabeledContent("Created") { Text(task.createdAt, format: .dateTime.day().month().year()) }
            LabeledContent("Updated") { Text(task.updatedAt, format: .relative(presentation: .named)) }
            LabeledContent("Sync") {
                Text(task.syncState.isPending ? "Waiting to sync" : "Synced")
            }
        }
        .font(.footnote)
    }

    @ToolbarContentBuilder
    private func toolbar(for task: TaskItem) -> some ToolbarContent {
        if model.canEditDetails || model.canChangeStatus {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { onEdit(task) }
                    .accessibilityIdentifier("taskDetail.edit")
            }
        }
        if model.canDelete {
            ToolbarItem(placement: .bottomBar) {
                Button("Delete Task", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                    .accessibilityIdentifier("taskDetail.delete")
            }
        }
    }

    private func statusBinding(for task: TaskItem) -> Binding<TaskStatus> {
        Binding(
            get: { task.status },
            set: { model.requestStatus($0) }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.dismissError() } })
    }
}
