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

    // Set by glance surfaces (dropdown rows) before opening the detail
    // window. The window consumes it on appear / onChange, then clears it.
    public var pendingRoute: AppRoute?

    // Stamped by AppDelegate after each completed scan; Overview displays it.
    public var lastScanDate: Date?

    // True while a scan is in flight. Preferences disables the "Reset all
    // data" button when this is true to avoid racing the snapshot writer.
    public var scanInProgress: Bool = false

    // Mirror of the user's configured stale threshold, set by AppDelegate from
    // PreferencesStore at launch and on each rescan. Used only for display copy
    // ("…N+ days"); a mid-session preference change is reflected on the next
    // scan, matching when the stale filter itself changes. (C7)
    public var staleThresholdDays: Int = 90

    // True when the snapshot store could not be opened — diff/stale history is
    // unavailable, which is NOT the same as "no changes yet." (C2)
    public var snapshotStoreUnavailable: Bool = false
    // True when a diff query errored (vs. genuinely having no prior snapshot). (C2)
    public var diffUnavailable: Bool = false

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
        self.staleThresholdDays = staleThresholdDays
    }

    public var hasUnreviewedChanges: Bool {
        guard let latest = latestSnapshotID else { return false }
        let unreviewed = lastReviewedSnapshotID != latest
        let anyContent = (latestDiffYesterday?.hasContent ?? false)
            || (latestDiffWeek?.hasContent ?? false)
        return unreviewed && anyContent
    }

    /// The diff window glance surfaces summarize: yesterday when it has
    /// content, otherwise the 7-day fallback. (Single source of truth — the
    /// dropdown and sidebar previously each re-derived this.)
    public var activeDiff: SnapshotDiffs? {
        if let primary = latestDiffYesterday, primary.hasContent { return primary }
        return latestDiffWeek
    }

    // TCC `changed` (auth-value flips) is intentionally excluded: DiffTabView does
    // not render TCC changed rows today (deferred to the v0.8.x model-fidelity slice).
    // BTM and LaunchAgent `changed` ARE included because DiffTabView renders those
    // rows (disposition flips, state flips) — a flips-only diff must show a non-zero
    // badge/count.
    public var recentChangeEventCount: Int {
        guard let diff = activeDiff else { return 0 }
        return diff.tcc.added.count + diff.tcc.removed.count
            + diff.btm.added.count + diff.btm.removed.count + diff.btm.changed.count
            + diff.launchAgents.added.count + diff.launchAgents.removed.count + diff.launchAgents.changed.count
    }

    public var attentionState: AttentionState {
        AttentionState.evaluate(
            tccError: tccScanError,
            btmError: btmScanError,
            launchAgentError: launchAgentScanError
        )
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

    // VoiceOver-readable mirror of `menuBarSymbolName` — the icon's state is
    // otherwise conveyed only by SF Symbol swap, which a VoiceOver user can't
    // perceive. Same precedence as the symbol. (A1)
    public var menuBarAccessibilityLabel: String {
        if tccScanError != nil || btmScanError != nil || launchAgentScanError != nil {
            return String(localized: "Permission Pulse — scan error, action needed")
        }
        if hasUnreviewedChanges {
            return String(localized: "Permission Pulse — unreviewed changes")
        }
        if micInUse && cameraInUse {
            return String(localized: "Permission Pulse — microphone and camera in use")
        }
        if cameraInUse { return String(localized: "Permission Pulse — camera in use") }
        if micInUse { return String(localized: "Permission Pulse — microphone in use") }
        return String(localized: "Permission Pulse")
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
