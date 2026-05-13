import Foundation
import Observation
import PermissionsCore

@Observable
@MainActor
public final class AppViewModel {
    public enum DataSource: Sendable {
        case mock
        case live
    }

    public var grants: [PermissionGrant]
    public var launchAgents: [LaunchAgentItem]
    public var dataSource: DataSource

    public init(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        dataSource: DataSource = .mock
    ) {
        self.grants = grants
        self.launchAgents = launchAgents
        self.dataSource = dataSource
    }
}
