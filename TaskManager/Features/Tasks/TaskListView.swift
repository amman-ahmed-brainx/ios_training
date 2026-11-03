import SwiftUI

/// The user's tasks with search, filters, sort, swipe actions and sync status.
struct TaskListView: View {
    @State private var model: TaskListViewModel
    @State private var pendingDeletion: TaskItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let onAdd: () -> Void
    private let onShowSettings: () -> Void

    init(model: TaskListViewModel, onAdd: @escaping () -> Void, onShowSettings: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onAdd = onAdd
        self.onShowSettings = onShowSettings
    }

    var body: some View {
        content
            .navigationTitle("Tasks")
            .searchable(text: $model.query.searchText, prompt: Text("Search titles and notes"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape", action: onShowSettings)
                        .accessibilityIdentifier("taskList.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TaskFilterMenu(query: $model.query)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { await model.observe() }
            .task { await model.observeSync() }
            .confirmationDialog(
                "Delete this task?",
                isPresented: isConfirmingDeletion,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { task in
                Button("Delete", role: .destructive) {
                    Task { await model.delete(task) }
                }
                .accessibilityIdentifier("taskList.confirmDelete")
            } message: { task in
                Text("“\(task.title)” will be deleted for everyone it's shared with.")
            }
            .alert("Couldn't Update Task", isPresented: isShowingError) {
                Button("OK", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.actionError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading Tasks")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Something Went Wrong", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded where model.tasks.isEmpty:
            EmptyStateView(systemImage: "checklist", title: "No Tasks", message: "Tap + to add your first task.") {
                Button("Add Task", action: onAdd)
                    .buttonStyle(.primary)
                    .fixedSize()
            }
        case .loaded where model.visibleTasks.isEmpty:
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No Matching Tasks",
                message: "Try a different search or clear the filters."
            ) {
                if model.query.hasActiveFilters {
                    Button("Clear Filters") { model.clearFilters() }
                        .buttonStyle(.secondary)
                        .fixedSize()
                }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List(model.visibleTasks) { task in
            NavigationLink(value: AppRoute.taskDetail(taskId: task.id)) {
                TaskRow(task: task, isOverdue: model.isOverdue(task), isShared: task.ownerId != model.userId)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if model.canChangeStatus(task) {
                    Button {
                        Task { await model.toggleCompletion(of: task) }
                    } label: {
                        completionLabel(for: task)
                    }
                    .tint(Palette.statusDone)
                }
            }
            .swipeActions(edge: .trailing) {
                if model.canDelete(task) {
                    Button(role: .destructive) {
                        pendingDeletion = task
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .contextMenu { contextMenu(for: task) }
            .accessibilityActions {
                // Swipe actions are hard to discover with VoiceOver; offer them as rotor actions too.
                if model.canChangeStatus(task) {
                    Button(task.status == .done ? "Mark as To Do" : "Complete") {
                        Task { await model.toggleCompletion(of: task) }
                    }
                }
                if model.canDelete(task) {
                    Button("Delete") { pendingDeletion = task }
                }
            }
            // The id, not the title: titles are user-editable and can repeat.
            .accessibilityIdentifier("taskRow.\(task.id)")
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
        .animation(reduceMotion ? nil : .default, value: model.visibleTasks)
    }

    @ViewBuilder
    private func contextMenu(for task: TaskItem) -> some View {
        if model.canChangeStatus(task) {
            ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { status in
                Button(status.title, systemImage: status.systemImage) {
                    Task { await model.setStatus(status, for: task) }
                }
            }
        }
        if model.canDelete(task) {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = task }
        }
    }

    private func completionLabel(for task: TaskItem) -> some View {
        task.status == .done
            ? Label("Mark as To Do", systemImage: "arrow.uturn.backward.circle")
            : Label("Complete", systemImage: "checkmark.circle")
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            if model.loadState == .loaded && !model.tasks.isEmpty {
                SyncStatusBanner(status: model.bannerStatus)
            }
            Spacer(minLength: Spacing.small)
            FloatingAddButton(label: "Add Task", action: onAdd)
                .accessibilityIdentifier("taskList.add")
        }
        .padding(.horizontal, Spacing.large)
        .padding(.bottom, Spacing.small)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.dismissError() } })
    }
}

#if DEBUG
#Preview("Empty") {
    NavigationStack {
        TaskListView(
            model: AppEnvironment.preview.makeTaskListViewModel(session: .init(uid: "uitest-user", email: "", displayName: nil)),
            onAdd: {},
            onShowSettings: {}
        )
    }
}
#endif
