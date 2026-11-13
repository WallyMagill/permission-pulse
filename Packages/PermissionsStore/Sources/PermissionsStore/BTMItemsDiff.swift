import Foundation
import PermissionsCore

public struct BTMItemsDiff: Sendable, Equatable {
    public let added: [BTMItem]
    public let removed: [BTMItem]
    // Items with the same scope and identifier whose disposition or type
    // differs. Metadata-only churn (names, dates, raw bits) is not a change.
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
