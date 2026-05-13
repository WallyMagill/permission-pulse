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
    public var tccDataSource: DataSource
    public var launchAgentsDataSource: DataSource

    public init(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        tccDataSource: DataSource = .mock,
        launchAgentsDataSource: DataSource = .mock
    ) {
        self.grants = grants
        self.launchAgents = launchAgents
        self.tccDataSource = tccDataSource
        self.launchAgentsDataSource = launchAgentsDataSource
    }
}
