import Foundation
import Observation
import PermissionsCore
import PermissionsStore

#if canImport(AppKit)
import AppKit
#endif

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

    // v0.5.0 snapshot/diff/stale state.
    public var latestSnapshotID: SnapshotID?
    public var lastReviewedSnapshotID: SnapshotID?
    public var latestDiffYesterday: SnapshotDiffs?
    public var latestDiffWeek: SnapshotDiffs?
    public var staleApps: [StaleApp]

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
        showFDASheetOnDetail: Bool = false,
        latestSnapshotID: SnapshotID? = nil,
        lastReviewedSnapshotID: SnapshotID? = nil,
        latestDiffYesterday: SnapshotDiffs? = nil,
        latestDiffWeek: SnapshotDiffs? = nil,
        staleApps: [StaleApp] = []
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
        self.latestSnapshotID = latestSnapshotID
        self.lastReviewedSnapshotID = lastReviewedSnapshotID
        self.latestDiffYesterday = latestDiffYesterday
        self.latestDiffWeek = latestDiffWeek
        self.staleApps = staleApps
    }

    public var hasUnreviewedChanges: Bool {
        guard let latest = latestSnapshotID else { return false }
        let unreviewed = lastReviewedSnapshotID != latest
        let anyContent = (latestDiffYesterday?.hasContent ?? false)
            || (latestDiffWeek?.hasContent ?? false)
        return unreviewed && anyContent
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
