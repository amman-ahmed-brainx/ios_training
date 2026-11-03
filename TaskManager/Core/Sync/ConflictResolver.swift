/// Merges a locally pending task with the backend's copy.
///
/// Policy: last write wins by `updatedAt`, the remote copy wins ties. `status` merges on its own
/// clock (`statusUpdatedAt`), so a collaborator's status change is not lost to an owner's stale
/// offline edit of other fields, and vice versa.
enum ConflictResolver {
    struct Outcome: Equatable, Sendable {
        let merged: VersionedTask
        /// Some local change is newer than the backend's, so the row must still be pushed.
        let needsPush: Bool
    }

    static func resolve(local: VersionedTask, remote: VersionedTask) -> Outcome {
        let localFieldsWin = local.item.updatedAt > remote.item.updatedAt
        let localStatusWins = local.statusUpdatedAt > remote.statusUpdatedAt

        var merged = localFieldsWin ? local : remote
        merged.item.status = localStatusWins ? local.item.status : remote.item.status
        merged.statusUpdatedAt = max(local.statusUpdatedAt, remote.statusUpdatedAt)
        merged.item.updatedAt = max(local.item.updatedAt, remote.item.updatedAt)
        return Outcome(merged: merged, needsPush: localFieldsWin || localStatusWins)
    }
}
