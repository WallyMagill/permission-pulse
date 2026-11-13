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
    public var tccAvailability: ScanAvailability
    /// Permission sources this macOS version does not expose (see
    /// `ScannerOutput.unavailableSources`). Non-empty narrows what a complete
    /// Permissions scan covers.
    public var tccUnavailableSources: [ScannerSource] = []
    public var btmAvailability: ScanAvailability
    public var launchAgentAvailability: ScanAvailability
    public var micInUse: Bool
    public var cameraInUse: Bool
    public var mediaDataSource: DataSource

    // v0.5.0 snapshot/diff/stale state.
    public var latestSnapshotID: SnapshotID?
    public var lastReviewedSnapshotID: SnapshotID?
    public var latestDiffSinceReview: SnapshotDiffs?
    /// When the latest stored snapshot was taken; nil until history exists.
    public var latestSnapshotDate: Date?
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

    /// Why the snapshot store could not be opened; nil when it is open.
    /// History is unavailable, which is NOT the same as "no changes yet." (C2)
    public var snapshotStoreProblem: SnapshotStoreProblem?
    public var snapshotStoreUnavailable: Bool {
        get { snapshotStoreProblem != nil }
        set { snapshotStoreProblem = newValue ? (snapshotStoreProblem ?? .unavailable) : nil }
    }
    // True when a diff query errored (vs. genuinely having no prior snapshot). (C2)
    public var diffUnavailable: Bool = false
    /// True when the latest scan's snapshot could not be saved, so the diffs
    /// shown stop at the previous snapshot.
    public var snapshotWriteFailed: Bool = false

    /// Applies Recent Changes dismissals and snoozes to every count.
    public var dismissedDiffEntries: DismissedDiffEntryStore?
    /// True while the detail window shows Recent Changes.
    public var isViewingRecentChanges: Bool = false
    /// The Recent Changes window picker's selection.
    public var recentChangesWindow: RecentChangesWindow = .sinceLastReview

    public init(
        grants: [PermissionGrant] = [],
        launchAgents: [LaunchAgentItem] = [],
        btmItems: [BTMItem] = [],
        tccDataSource: DataSource = .mock,
        launchAgentsDataSource: DataSource = .mock,
        btmDataSource: DataSource = .mock,
        tccAvailability: ScanAvailability = .never,
        btmAvailability: ScanAvailability = .never,
        launchAgentAvailability: ScanAvailability = .never,
        tccScanError: ScannerError? = nil,
        btmScanError: ScannerError? = nil,
        launchAgentScanError: ScannerError? = nil,
        micInUse: Bool = false,
        cameraInUse: Bool = false,
        mediaDataSource: DataSource = .mock,
        latestSnapshotID: SnapshotID? = nil,
        lastReviewedSnapshotID: SnapshotID? = nil,
        latestDiffSinceReview: SnapshotDiffs? = nil,
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
        self.tccAvailability = Self.initialAvailability(tccAvailability, error: tccScanError)
        self.btmAvailability = Self.initialAvailability(btmAvailability, error: btmScanError)
        self.launchAgentAvailability = Self.initialAvailability(
            launchAgentAvailability,
            error: launchAgentScanError
        )
        self.micInUse = micInUse
        self.cameraInUse = cameraInUse
        self.mediaDataSource = mediaDataSource
        self.latestSnapshotID = latestSnapshotID
        self.lastReviewedSnapshotID = lastReviewedSnapshotID
        self.latestDiffSinceReview = latestDiffSinceReview
        self.latestDiffWeek = latestDiffWeek
        self.staleApps = staleApps
        self.staleThresholdDays = staleThresholdDays
    }

    /// The changes in `diff` the user has not dismissed or snoozed — what
    /// Recent Changes lists, the badge counts, and the digest reports.
    public func visibleEntries(of diff: SnapshotDiffs?, asOf date: Date = Date()) -> [DiffEntry] {
        guard let diff else { return [] }
        return dismissedDiffEntries?.visibleEntries(in: diff, asOf: date) ?? diff.entries
    }

    /// Visible changes since the last review. Zero while the user is on
    /// Recent Changes: nothing there is unreviewed until they leave.
    public var unreviewedChangeCount: Int {
        guard !isViewingRecentChanges,
              let latest = latestSnapshotID,
              lastReviewedSnapshotID != latest else { return 0 }
        return visibleEntries(of: latestDiffSinceReview).count
    }

    public var hasUnreviewedChanges: Bool {
        unreviewedChangeCount > 0
    }

    /// Records a "Skip forever" and drops the app from the current list, so
    /// the sidebar and dropdown counts fall without waiting for a rescan.
    public func skipStaleAppForever(stableKey: String, in store: DismissedStaleAppStore) {
        store.skipForever(stableKey: stableKey)
        staleApps.removeAll { $0.app.stableKey == stableKey }
    }

    public var attentionState: AttentionState {
        AttentionState.evaluate(
            tccAvailability: tccAvailability,
            btmAvailability: btmAvailability,
            launchAgentAvailability: launchAgentAvailability
        )
    }

    // Compatibility accessors for existing views/tests while availability is
    // the only stored scan truth.
    public var tccScanError: ScannerError? {
        get { tccAvailability.error }
        set { tccAvailability = Self.updating(tccAvailability, error: newValue) }
    }

    public var btmScanError: ScannerError? {
        get { btmAvailability.error }
        set { btmAvailability = Self.updating(btmAvailability, error: newValue) }
    }

    public var launchAgentScanError: ScannerError? {
        get { launchAgentAvailability.error }
        set { launchAgentAvailability = Self.updating(launchAgentAvailability, error: newValue) }
    }

    /// Live microphone or camera use wins: it is happening now, while a
    /// warning or unreviewed change can wait for the dropdown.
    public var menuBarSymbolName: String {
        if micInUse && cameraInUse { return "video.badge.waveform" }
        if cameraInUse { return "video.fill" }
        if micInUse { return "mic.fill" }
        if attentionState != .clean {
            return "exclamationmark.shield.fill"
        }
        if hasUnreviewedChanges {
            return Self.unreviewedSymbolName
        }
        return "shield.lefthalf.filled"
    }

    // VoiceOver-readable mirror of `menuBarSymbolName` — the icon's state is
    // otherwise conveyed only by SF Symbol swap, which a VoiceOver user can't
    // perceive. Names live media use and any warning together, since the
    // symbol can show only one of them. (A1)
    public var menuBarAccessibilityLabel: String {
        let parts = [mediaAccessibilityPart, attentionAccessibilityPart ?? unreviewedAccessibilityPart]
            .compactMap { $0 }
        guard !parts.isEmpty else { return String(localized: "Permission Pulse") }
        let details = parts.joined(separator: String(localized: "; "))
        return String(localized: "Permission Pulse — \(details)")
    }

    private var mediaAccessibilityPart: String? {
        if micInUse && cameraInUse { return String(localized: "microphone and camera in use") }
        if cameraInUse { return String(localized: "camera in use") }
        if micInUse { return String(localized: "microphone in use") }
        return nil
    }

    private var attentionAccessibilityPart: String? {
        switch attentionState {
        case .degradedData: String(localized: "degraded scan data, action needed")
        case .staleData: String(localized: "stale scan data, action needed")
        case .scanFailed: String(localized: "scan failed, no results available, action needed")
        case .fdaDenied: String(localized: "Full Disk Access is off")
        case .btmOnlyFDADenied: String(localized: "Full Disk Access is off for background items")
        case .schemaMismatch, .launchAgentError: String(localized: "scan error, action needed")
        case .clean: nil
        }
    }

    private var unreviewedAccessibilityPart: String? {
        hasUnreviewedChanges ? String(localized: "unreviewed changes") : nil
    }

    private static func initialAvailability(
        _ availability: ScanAvailability,
        error: ScannerError?
    ) -> ScanAvailability {
        guard let error else { return availability }
        return .failed(lastSuccessful: availability.lastSuccessful, error: error)
    }

    private static func updating(
        _ availability: ScanAvailability,
        error: ScannerError?
    ) -> ScanAvailability {
        guard let error else {
            if case .failed = availability { return .never }
            return availability
        }
        return .failed(lastSuccessful: availability.lastSuccessful, error: error)
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
