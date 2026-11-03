import SwiftUI

/// App settings. Only the account section exists so far.
struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var isConfirmingSignOut = false
    @State private var isImporting = false
    @Environment(\.dismiss) private var dismiss

    init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let name = model.session.displayName, !name.isEmpty {
                        LabeledContent("Name") { Text(verbatim: name) }
                    }
                    LabeledContent("Email") { Text(verbatim: model.session.email) }
                }
                Section("Reminders") {
                    Picker("Remind Me", selection: $model.leadTime) {
                        ForEach(ReminderLeadTime.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Button("Export Tasks as JSON", systemImage: "square.and.arrow.up") {
                        Task { await model.exportTasks() }
                    }
                    if let url = model.exportURL {
                        ShareLink(item: url) { Label("Share Export", systemImage: "doc.text") }
                    }
                    Button("Import Tasks from JSON", systemImage: "square.and.arrow.down") { isImporting = true }
                    if let progress = model.transferProgress {
                        ProgressView(value: progress).accessibilityLabel(Text("Transferring tasks"))
                    }
                    #if DEBUG
                    Button("Generate 1,000 Sample Tasks", systemImage: "hammer") {
                        Task { await model.generateSampleTasks() }
                    }
                    #endif
                } header: {
                    Text("Data")
                }
                .disabled(model.transferProgress != nil)
                if model.isSyncAvailable {
                    Section("Sync") {
                        LabeledContent("Status") {
                            Text(model.syncStatus.isOnline ? (model.syncStatus.isSyncing ? "Syncing…" : "Online") : "Offline")
                        }
                        LabeledContent("Pending Changes") { Text(model.syncStatus.pendingCount, format: .number) }
                        Button("Sync Now") { Task { await model.syncNow() } }
                            .disabled(!model.syncStatus.isOnline || model.syncStatus.isSyncing)
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
                        .disabled(model.isSigningOut)
                        .accessibilityIdentifier("settings.signOut")
                } footer: {
                    Text("Signing out removes your tasks from this device, including changes that haven't synced yet.")
                }
            }
            .task { await model.observeSync() }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): Task { await model.importTasks(from: url) }
                case .failure: model.reportImportPickerFailure()
                }
            }
            .alert("Tasks", isPresented: Binding(
                get: { model.transferMessage != nil },
                set: { if !$0 { model.dismissTransferMessage() } }
            )) {
                Button("OK", role: .cancel) { model.dismissTransferMessage() }
            } message: {
                Text(model.transferMessage ?? "")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await model.signOut() }
                }
                .accessibilityIdentifier("settings.confirmSignOut")
            }
        }
    }
}

#if DEBUG
#Preview("Settings, dark") {
    SettingsView(model: AppEnvironment.preview.makeSettingsViewModel(
        session: AuthSession(uid: "uitest-user", email: "test@example.com", displayName: "Test User")
    ))
    .preferredColorScheme(.dark)
}
#endif
