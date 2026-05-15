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
    public var micInUse: Bool
    public var cameraInUse: Bool
    public var mediaDataSource: DataSource
    public var showFDASheetOnDetail: Bool

    public init(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        btmItems: [BTMItem] = [],
        tccDataSource: DataSource = .mock,
        launchAgentsDataSource: DataSource = .mock,
        btmDataSource: DataSource = .mock,
        tccScanError: ScannerError? = nil,
        btmScanError: ScannerError? = nil,
        micInUse: Bool = false,
        cameraInUse: Bool = false,
        mediaDataSource: DataSource = .mock,
        showFDASheetOnDetail: Bool = false
    ) {
        self.grants = grants
        self.launchAgents = launchAgents
        self.btmItems = btmItems
        self.tccDataSource = tccDataSource
        self.launchAgentsDataSource = launchAgentsDataSource
        self.btmDataSource = btmDataSource
        self.tccScanError = tccScanError
        self.btmScanError = btmScanError
        self.micInUse = micInUse
        self.cameraInUse = cameraInUse
        self.mediaDataSource = mediaDataSource
        self.showFDASheetOnDetail = showFDASheetOnDetail
    }

    public var menuBarSymbolName: String {
        if tccScanError != nil || btmScanError != nil {
            return "exclamationmark.shield.fill"
        }
        if micInUse && cameraInUse { return "video.badge.waveform" }
        if cameraInUse { return "video.fill" }
        if micInUse { return "mic.fill" }
        return "shield.lefthalf.filled"
    }
}
