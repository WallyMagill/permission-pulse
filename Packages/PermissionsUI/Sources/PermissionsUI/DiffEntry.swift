import Foundation
import PermissionsCore
import PermissionsStore

/// One change between two snapshots, as every surface counts and renders it:
/// the Recent Changes rows, the badge and dropdown count, and the digest.
public enum DiffEntry: Sendable, Hashable, Identifiable {
    case granted(PermissionGrant)
    case revoked(PermissionGrant)
    case permissionChanged(DomainChange<PermissionGrant>)
    case btmAdded(BTMItem)
    case btmRemoved(BTMItem)
    case btmDispositionFlipped(DomainChange<BTMItem>)
    case launchAgentAdded(LaunchAgentItem)
    case launchAgentRemoved(LaunchAgentItem)
    case launchAgentFlipped(DomainChange<LaunchAgentItem>)

    public enum Change: Sendable, Equatable {
        case added
        case removed
        case changed
    }

    /// Stable across snapshots; the key dismissals are stored under.
    public var id: String { DiffEntryKey.key(for: self) }

    public var domain: HistoryDomain {
        switch self {
        case .granted, .revoked, .permissionChanged: .tcc
        case .btmAdded, .btmRemoved, .btmDispositionFlipped: .btm
        case .launchAgentAdded, .launchAgentRemoved, .launchAgentFlipped: .launchAgents
        }
    }

    public var change: Change {
        switch self {
        case .granted, .btmAdded, .launchAgentAdded: .added
        case .revoked, .btmRemoved, .launchAgentRemoved: .removed
        case .permissionChanged, .btmDispositionFlipped, .launchAgentFlipped: .changed
        }
    }

    /// The one-line description the Recent Changes row shows.
    @MainActor public var summary: String { ChangeRow.summary(for: self) }
}

extension SnapshotDiffs {
    /// Every change in the diff, grouped by domain: Permissions, Background
    /// Items, then Launch Agents; within a domain added, removed, changed.
    public var entries: [DiffEntry] {
        tcc.added.map(DiffEntry.granted)
            + tcc.removed.map(DiffEntry.revoked)
            + tcc.changed.map(DiffEntry.permissionChanged)
            + btm.added.map(DiffEntry.btmAdded)
            + btm.removed.map(DiffEntry.btmRemoved)
            + btm.changed.map(DiffEntry.btmDispositionFlipped)
            + launchAgents.added.map(DiffEntry.launchAgentAdded)
            + launchAgents.removed.map(DiffEntry.launchAgentRemoved)
            + launchAgents.changed.map(DiffEntry.launchAgentFlipped)
    }
}
