import Foundation
import PermissionsCore

public struct LaunchAgentsDiff: Sendable, Equatable {
    public let added: [LaunchAgentItem]
    public let removed: [LaunchAgentItem]
    public let changed: [DomainChange<LaunchAgentItem>]

    public init(
        added: [LaunchAgentItem],
        removed: [LaunchAgentItem],
        changed: [DomainChange<LaunchAgentItem>] = []
    ) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public var hasContent: Bool {
        !added.isEmpty || !removed.isEmpty || !changed.isEmpty
    }
}
