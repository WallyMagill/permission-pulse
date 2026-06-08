import Foundation
import PermissionsCore
import PermissionsStore

/// Pure mapper from a `ChangeRow.Kind` to a stable string key used by the
/// `DismissedDiffEntryStore`. Keys deliberately omit the snapshot ID so a
/// dismissal carries across future snapshots — a user who hides a TCC
/// grant doesn't want it to reappear when tomorrow's snapshot rolls in.
///
/// All keys are computed from the same identity fields the diff engine
/// uses (`SnapshotStore.tccGrantIdentityKey` / `btmItemIdentityKey` /
/// `launchAgentIdentityKey`), so renames on either side fail together
/// rather than silently orphaning entries.
enum DiffEntryKey {
    static func key(for kind: ChangeRow.Kind) -> String {
        switch kind {
        case .granted(let g):
            return "tcc-granted|\(g.identityKey)"
        case .revoked(let g):
            return "tcc-revoked|\(g.identityKey)"
        case .btmAdded(let i):
            return "btm-added|\(i.identifier)"
        case .btmRemoved(let i):
            return "btm-removed|\(i.identifier)"
        case .btmDispositionFlipped(let change):
            return "btm-flip|\(change.after.identifier)"
        case .launchAgentAdded(let i):
            return "la-added|\(i.sourceDirectory.rawValue)|\(i.label)"
        case .launchAgentRemoved(let i):
            return "la-removed|\(i.sourceDirectory.rawValue)|\(i.label)"
        case .launchAgentFlipped(let change):
            return "la-flip|\(change.after.sourceDirectory.rawValue)|\(change.after.label)"
        }
    }
}
