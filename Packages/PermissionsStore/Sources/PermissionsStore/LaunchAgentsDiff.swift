import Foundation
import PermissionsCore

public struct LaunchAgentsDiff: Sendable, Equatable {
    public let added: [LaunchAgentItem]
    public let removed: [LaunchAgentItem]

    public init(added: [LaunchAgentItem], removed: [LaunchAgentItem]) {
        self.added = added
        self.removed = removed
    }
}
