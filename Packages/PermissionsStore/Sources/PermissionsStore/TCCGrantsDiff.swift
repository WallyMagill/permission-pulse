import Foundation
import PermissionsCore

public struct TCCGrantsDiff: Sendable, Equatable {
    public let added: [PermissionGrant]
    public let removed: [PermissionGrant]
    // v0.5.0 always emits empty `changed`; PermissionGrant does not carry
    // auth_value, so granted→denied looks like remove+add. Reserved for v0.6.0+
    // when auth_value is tracked.
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
