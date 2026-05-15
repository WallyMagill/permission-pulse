import Foundation
import PermissionsCore

public struct BTMItemsDiff: Sendable, Equatable {
    public let added: [BTMItem]
    public let removed: [BTMItem]
    // Picks up disposition flips, scope changes, name renames — anything that
    // makes two BTMItems with the same identifier non-equal under Hashable.
    public let changed: [DomainChange<BTMItem>]

    public init(
        added: [BTMItem],
        removed: [BTMItem],
        changed: [DomainChange<BTMItem>] = []
    ) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public var hasContent: Bool {
        !added.isEmpty || !removed.isEmpty || !changed.isEmpty
    }
}
