import Foundation
import PermissionsCore

public struct BTMItemsDiff: Sendable, Equatable {
    public let added: [BTMItem]
    public let removed: [BTMItem]
    // Items with the same scope and identifier whose disposition, type or
    // signing team differs. Metadata-only churn (names, dates, raw bits) is
    // not a change.
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

extension DomainChange where T == BTMItem {
    /// Both sides name a signing team and the teams differ: a different
    /// developer signed the same identifier. A team missing on either side
    /// is not evidence of a different developer.
    public var teamIdentifierChanged: Bool {
        guard let before = Self.team(before), let after = Self.team(after) else { return false }
        return before != after
    }

    private static func team(_ item: BTMItem) -> String? {
        guard let team = item.teamIdentifier, !team.isEmpty else { return nil }
        return team
    }
}
