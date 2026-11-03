import SwiftUI

/// App settings. Only the account section exists so far.
struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var isConfirmingSignOut = false
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
