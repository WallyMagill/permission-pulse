import Foundation
import PermissionsCore

public struct TCCGrantsDiff: Sendable, Equatable {
    public let added: [PermissionGrant]
    public let removed: [PermissionGrant]
    // `changed` contains persisted value transitions between grants with the same
    // stable identity, including authValue shifts (2 = allowed <-> 3 = limited).
    // DiffTabView renders these alongside added and removed grants, and ChangeRow
    // includes their before/after values in Recent Changes search.
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
