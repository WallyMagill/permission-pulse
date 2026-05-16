import Foundation
import OSLog
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI

/// Orchestrates the "Reset all data" cascade triggered from Preferences.
///
/// Cancels pending notifications, deletes `snapshots.db`, re-inits the
/// store at the same path, removes every `com.wallymagill.permissionpulse.*`
/// UserDefaults key (preserving NSWindow/NSStatusItem keys that macOS
/// auto-writes under our bundle domain), wipes the live ViewModel state,
/// and triggers a fresh scan + schedule reconciliation.
///
/// Welcome window is deliberately NOT re-shown this session (the user
/// invoked reset on purpose); on next cold launch `hasSeenWelcome` is
/// gone so the Welcome window comes back.
///
/// Idempotent: a second call with no DB and empty defaults completes the
/// same way without error.
@MainActor
final class ResetAllDataService {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "reset-all-data"
    )

    static let bundlePrefix = "com.wallymagill.permissionpulse."

    private let viewModel: AppViewModel
    private let snapshotPathURL: URL
    private let onSnapshotStoreReinit: (SnapshotStore) -> Void
    private let weeklyDigestCoordinator: WeeklyDigestCoordinator
    private let defaults: UserDefaults
    private let rescan: @MainActor () async -> Void

    init(
        viewModel: AppViewModel,
        snapshotPathURL: URL,
        onSnapshotStoreReinit: @escaping (SnapshotStore) -> Void,
        weeklyDigestCoordinator: WeeklyDigestCoordinator,
        defaults: UserDefaults = .standard,
        rescan: @MainActor @escaping () async -> Void
    ) {
        self.viewModel = viewModel
        self.snapshotPathURL = snapshotPathURL
        self.onSnapshotStoreReinit = onSnapshotStoreReinit
        self.weeklyDigestCoordinator = weeklyDigestCoordinator
        self.defaults = defaults
        self.rescan = rescan
    }

    func reset() async {
        // 1. Cancel pending digest notifications.
        await weeklyDigestCoordinator.scheduler.cancelAll(
            matchingPrefix: WeeklyDigestCoordinator.identifierPrefix
        )

        // 2. Delete the snapshots DB (idempotent — try?).
        try? FileManager.default.removeItem(at: snapshotPathURL)

        // 3. Re-init the snapshot store at the same path so subsequent
        //    scans have somewhere to write.
        do {
            let newStore = try SnapshotStore(path: snapshotPathURL.path(percentEncoded: false))
            onSnapshotStoreReinit(newStore)
        } catch {
            Self.logger.error(
                "Failed to re-init snapshot store after reset: \(error.localizedDescription, privacy: .public)"
            )
        }

        // 4. Remove every PP UserDefaults key, preserve everything else
        //    (NSWindow/NSStatusItem/NSSplitView auto-writes under our domain).
        let keysToRemove = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.bundlePrefix) }
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        // 5. Wipe in-memory ViewModel state.
        viewModel.grants = []
        viewModel.launchAgents = []
        viewModel.btmItems = []
        viewModel.latestDiffYesterday = nil
        viewModel.latestDiffWeek = nil
        viewModel.staleApps = []
        viewModel.latestSnapshotID = nil
        viewModel.lastReviewedSnapshotID = nil

        // 6. Trigger a fresh scan so the UI repopulates immediately.
        await rescan()
    }
}

