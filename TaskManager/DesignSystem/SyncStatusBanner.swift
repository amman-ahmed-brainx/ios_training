import SwiftUI

/// Compact floating status of local changes versus the backend.
struct SyncStatusBanner: View {
    enum Status: Equatable {
        case synced
        case pending(count: Int)
        /// Shown once the network monitor arrives with offline sync; the list passes it then.
        case offline(pendingCount: Int)
    }

    let status: Status

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Metrics.minHitTarget)
            .floatingGlass(in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var title: String {
        switch status {
        case .synced:
            String(localized: "All changes synced")
        case .pending(let count):
            String(localized: "\(count) changes waiting to sync")
        case .offline(let pendingCount) where pendingCount > 0:
            String(localized: "Offline · \(pendingCount) changes will sync later")
        case .offline:
            String(localized: "Offline")
        }
    }

    private var systemImage: String {
        switch status {
        case .synced: "checkmark.icloud"
        case .pending: "arrow.triangle.2.circlepath.icloud"
        case .offline: "icloud.slash"
        }
    }
}

#Preview {
    VStack(spacing: Spacing.large) {
        SyncStatusBanner(status: .synced)
        SyncStatusBanner(status: .pending(count: 3))
        SyncStatusBanner(status: .offline(pendingCount: 2))
    }
    .padding()
    .background(Color(.launchBackground))
}
