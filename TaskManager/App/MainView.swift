import SwiftUI

/// Signed-in root: the task list inside a router-driven navigation stack, plus its sheets.
struct MainView: View {
    /// What the editor sheet is open for.
    private enum EditorRequest: Identifiable {
        case create
        case edit(TaskItem)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let task): task.id
            }
        }

        var task: TaskItem? {
            if case .edit(let task) = self { task } else { nil }
        }
    }

    private let environment: AppEnvironment
    private let session: AuthSession
    @State private var editor: EditorRequest?
    @State private var isShowingSettings = false

    init(environment: AppEnvironment, session: AuthSession) {
        self.environment = environment
        self.session = session
    }

    var body: some View {
        @Bindable var router = environment.router
        NavigationStack(path: $router.path) {
            TaskListView(
                model: environment.makeTaskListViewModel(session: session),
                onAdd: { editor = .create },
                onShowSettings: { isShowingSettings = true }
            )
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .taskDetail(let taskId):
                    TaskDetailView(model: environment.makeTaskDetailViewModel(taskId: taskId, session: session)) {
                        editor = .edit($0)
                    }
                }
            }
        }
        .sheet(item: $editor) { request in
            TaskEditorView(model: environment.makeTaskEditorViewModel(editing: request.task, session: session))
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: environment.makeSettingsViewModel(session: session))
        }
        .onDisappear { router.reset() }
    }
}

#if DEBUG
#Preview {
    MainView(environment: .preview, session: AuthSession(uid: "uitest-user", email: "test@example.com", displayName: "Test User"))
}
#endif
