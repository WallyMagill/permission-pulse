import Foundation
import PermissionsCore
import PermissionsStore

/// Pure mapper from a `DiffEntry` to a stable string key used by the
/// `DismissedDiffEntryStore`. Keys deliberately omit the snapshot ID so a
/// dismissal carries across future snapshots — a user who hides a TCC
/// grant doesn't want it to reappear when tomorrow's snapshot rolls in.
///
/// All keys are computed from the same identity fields the diff engine
/// uses (`SnapshotStore.tccGrantIdentityKey` / `btmItemIdentityKey` /
/// `launchAgentIdentityKey`), so renames on either side fail together
/// rather than silently orphaning entries. Change keys also carry the
/// before→after states, so dismissing one transition does not hide the
/// opposite one later.
enum DiffEntryKey {
    static func key(for kind: DiffEntry) -> String {
        switch kind {
        case .granted(let g):
            return "tcc-granted|\(g.identityKey)"
        case .revoked(let g):
            return "tcc-revoked|\(g.identityKey)"
        case .permissionChanged(let change):
            return "tcc-changed|\(change.after.identityKey)|\(change.before.authValue)-\(change.after.authValue)"
        case .btmAdded(let i):
            return "btm-added|\(i.identityKey)"
        case .btmRemoved(let i):
            return "btm-removed|\(i.identityKey)"
        case .btmDispositionFlipped(let change):
            return "btm-flip|\(change.after.identityKey)|\(btmTransitionToken(change))"
        case .launchAgentAdded(let i):
            return "la-added|\(i.sourceDirectory.rawValue)|\(i.label)"
        case .launchAgentRemoved(let i):
            return "la-removed|\(i.sourceDirectory.rawValue)|\(i.label)"
        case .launchAgentFlipped(let change):
            let token = LaunchAgentChangeDescription.dismissalToken(change)
            return "\(legacyLaunchAgentFlipKey(change))|\(token)"
        }
    }

    /// Every key whose dismissal hides this row: the current key plus any
    /// pre-v0.7.2 form still stored in UserDefaults.
    static func lookupKeys(for kind: DiffEntry) -> [String] {
        guard let legacy = legacyKey(for: kind) else { return [key(for: kind)] }
        return [key(for: kind), legacy]
    }

    /// The pre-v0.7.2 key for a row. Those keys named only the agent or the
    /// bare BTM identifier, with no scope or direction, so an old dismissal
    /// keeps hiding every matching row, as it did when stored.
    private static func legacyKey(for kind: DiffEntry) -> String? {
        switch kind {
        case .launchAgentFlipped(let change): legacyLaunchAgentFlipKey(change)
        case .btmAdded(let item): "btm-added|\(item.identifier)"
        case .btmRemoved(let item): "btm-removed|\(item.identifier)"
        case .btmDispositionFlipped(let change): "btm-flip|\(change.after.identifier)"
        default: nil
        }
    }

    private static func legacyLaunchAgentFlipKey(_ change: DomainChange<LaunchAgentItem>) -> String {
        "la-flip|\(change.after.sourceDirectory.rawValue)|\(change.after.label)"
    }

    private static func btmTransitionToken(_ change: DomainChange<BTMItem>) -> String {
        var token = "\(dispositionToken(change.before.disposition))-\(dispositionToken(change.after.disposition))"
        if change.before.type != change.after.type {
            token += "|type:\(change.before.type.rawValue)-\(change.after.type.rawValue)"
        }
        if change.teamIdentifierChanged {
            token += "|team:\(change.before.teamIdentifier ?? "")-\(change.after.teamIdentifier ?? "")"
        }
        return token
    }

    private static func dispositionToken(_ disposition: BTMItem.Disposition) -> String {
        switch disposition {
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .unknown(let raw): "unknown\(raw)"
        }
    }
}
