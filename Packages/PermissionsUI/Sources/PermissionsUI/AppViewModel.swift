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
    public var btmItems: [BTMItem]
    public var tccDataSource: DataSource
    public var launchAgentsDataSource: DataSource
    public var btmDataSource: DataSource
    public var tccScanError: ScannerError?
    public var btmScanError: ScannerError?

    public init(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        btmItems: [BTMItem] = [],
        tccDataSource: DataSource = .mock,
        launchAgentsDataSource: DataSource = .mock,
        btmDataSource: DataSource = .mock,
        tccScanError: ScannerError? = nil,
        btmScanError: ScannerError? = nil
    ) {
        self.grants = grants
        self.launchAgents = launchAgents
        self.btmItems = btmItems
        self.tccDataSource = tccDataSource
        self.launchAgentsDataSource = launchAgentsDataSource
        self.btmDataSource = btmDataSource
        self.tccScanError = tccScanError
        self.btmScanError = btmScanError
    }
}
