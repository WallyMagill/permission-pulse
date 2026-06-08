import Foundation
import PermissionsCore

public struct TCCGrantsDiff: Sendable, Equatable {
    public let added: [PermissionGrant]
    public let removed: [PermissionGrant]
    // `changed` is now populated when two grants share an identity but differ —
    // notably an auth_value shift (2 = allowed <-> 3 = limited), since auth_value is
    // captured on PermissionGrant but is NOT part of the identity key. The diff
    // engine emits these into `changed`; RENDERING TCC `changed` rows in the UI is
    // deferred to the v0.8.x model-fidelity slice (DiffTabView.tccRows maps only
    // .added/.removed today).
    public let changed: [DomainChange<PermissionGrant>]

    public init(
        added: [PermissionGrant],
        removed: [PermissionGrant],
        changed: [DomainChange<PermissionGrant>] = []
    ) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public var hasContent: Bool {
        !added.isEmpty || !removed.isEmpty || !changed.isEmpty
    }
}
