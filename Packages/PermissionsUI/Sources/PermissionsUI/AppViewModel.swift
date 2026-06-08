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

    public enum DetailMode: Sendable, Hashable {
        case current
        case whatChanged
    }

    public var grants: [PermissionGrant]
    public var launchAgents: [LaunchAgentItem]
    public var btmItems: [BTMItem]
    public var tccDataSource: DataSource
    public var launchAgentsDataSource: DataSource
    public var btmDataSource: DataSource
    public var tccScanError: ScannerError?
    public var btmScanError: ScannerError?
    public var launchAgentScanError: ScannerError?
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

    // Set by the menu-bar buttons before opening the detail window. The
    // window observes this and applies it on appear or via onChange, then
    // clears it back to nil.
    public var pendingDetailMode: DetailMode?

    // True while a scan is in flight. Preferences disables the "Reset all
    // data" button when this is true to avoid racing the snapshot writer.
    public var scanInProgress: Bool = false

    // Mirror of the user's configured stale threshold, set by AppDelegate from
    // PreferencesStore at launch and on each rescan. Used only for display copy
    // ("…N+ days"); a mid-session preference change is reflected on the next
    // scan, matching when the stale filter itself changes. (C7)
    public var staleThresholdDays: Int = 90

    public init(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        btmItems: [BTMItem] = [],
        tccDataSource: DataSource = .mock,
        launchAgentsDataSource: DataSource = .mock,
        btmDataSource: DataSource = .mock,
        tccScanError: ScannerError? = nil,
        btmScanError: ScannerError? = nil,
        launchAgentScanError: ScannerError? = nil,
        micInUse: Bool = false,
        cameraInUse: Bool = false,
        mediaDataSource: DataSource = .mock,
        showFDASheetOnDetail: Bool = false,
        latestSnapshotID: SnapshotID? = nil,
        lastReviewedSnapshotID: SnapshotID? = nil,
        latestDiffYesterday: SnapshotDiffs? = nil,
        latestDiffWeek: SnapshotDiffs? = nil,
        staleApps: [StaleApp] = [],
        pendingDetailMode: DetailMode? = nil,
        staleThresholdDays: Int = 90
    ) {
        self.grants = grants
        self.launchAgents = launchAgents
        self.btmItems = btmItems
        self.tccDataSource = tccDataSource
        self.launchAgentsDataSource = launchAgentsDataSource
        self.btmDataSource = btmDataSource
        self.tccScanError = tccScanError
        self.btmScanError = btmScanError
        self.launchAgentScanError = launchAgentScanError
        self.micInUse = micInUse
        self.cameraInUse = cameraInUse
        self.mediaDataSource = mediaDataSource
        self.showFDASheetOnDetail = showFDASheetOnDetail
        self.latestSnapshotID = latestSnapshotID
        self.lastReviewedSnapshotID = lastReviewedSnapshotID
        self.latestDiffYesterday = latestDiffYesterday
        self.latestDiffWeek = latestDiffWeek
        self.staleApps = staleApps
        self.pendingDetailMode = pendingDetailMode
        self.staleThresholdDays = staleThresholdDays
    }

    public var hasUnreviewedChanges: Bool {
        guard let latest = latestSnapshotID else { return false }
        let unreviewed = lastReviewedSnapshotID != latest
        let anyContent = (latestDiffYesterday?.hasContent ?? false)
            || (latestDiffWeek?.hasContent ?? false)
        return unreviewed && anyContent
    }

    public var menuBarSymbolName: String {
        if tccScanError != nil || btmScanError != nil || launchAgentScanError != nil {
            return "exclamationmark.shield.fill"
        }
        if hasUnreviewedChanges {
            return Self.unreviewedSymbolName
        }
        if micInUse && cameraInUse { return "video.badge.waveform" }
        if cameraInUse { return "video.fill" }
        if micInUse { return "mic.fill" }
        return "shield.lefthalf.filled"
    }

    // Verify the preferred symbol exists on this OS. `bell.badge.fill` has
    // shipped since Big Sur, but a one-time guard is cheap and survives
    // future SF Symbol renames.
    private static let unreviewedSymbolName: String = {
        #if canImport(AppKit)
        let preferred = "bell.badge.fill"
        if NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil {
            return preferred
        }
        return "exclamationmark.bubble.fill"
        #else
        return "bell.badge.fill"
        #endif
    }()
}
