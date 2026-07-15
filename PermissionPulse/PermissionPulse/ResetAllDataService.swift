import Foundation
import OSLog
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI

enum ResetPhase: Sendable, Equatable {
    case cancelNotifications
    case releaseHistory
    case deleteHistory
    case resetLiveStores
    case clearDefaults
    case recreateHistory
    case rescan
}

enum ResetResult: Sendable, Equatable {
    case completed(scanSucceeded: Bool)
    case failed(phase: ResetPhase, message: String)
}

protocol ResetFileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func removeItem(at url: URL) throws
}

extension FileManager: ResetFileManaging {}

/// Orchestrates the "Reset all data" cascade triggered from Preferences.
///
/// Cancels owned notifications, releases the history runtime, deletes the
/// SQLite main/WAL/SHM files, resets live stores and prefixed defaults, then
/// recreates history before clearing presentation state and rescanning.
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
    private let releaseSnapshotStore: @MainActor () -> Void
    private let onSnapshotStoreReinit: @MainActor (SnapshotStore) -> Void
    private let weeklyDigestCoordinator: WeeklyDigestCoordinator
    private let preferencesStore: PreferencesStore
    private let dismissedDiffEntries: DismissedDiffEntryStore
    private let dismissedStaleApps: DismissedStaleAppStore
    private let fileManager: any ResetFileManaging
    private let defaults: UserDefaults
    private let rescan: @MainActor () async -> Bool

    init(
        viewModel: AppViewModel,
        snapshotPathURL: URL,
        releaseSnapshotStore: @MainActor @escaping () -> Void,
        onSnapshotStoreReinit: @MainActor @escaping (SnapshotStore) -> Void,
        weeklyDigestCoordinator: WeeklyDigestCoordinator,
        preferencesStore: PreferencesStore,
        dismissedDiffEntries: DismissedDiffEntryStore,
        dismissedStaleApps: DismissedStaleAppStore,
        fileManager: any ResetFileManaging = FileManager.default,
        defaults: UserDefaults = .standard,
        rescan: @MainActor @escaping () async -> Bool
    ) {
        self.viewModel = viewModel
        self.snapshotPathURL = snapshotPathURL
        self.releaseSnapshotStore = releaseSnapshotStore
        self.onSnapshotStoreReinit = onSnapshotStoreReinit
        self.weeklyDigestCoordinator = weeklyDigestCoordinator
        self.preferencesStore = preferencesStore
        self.dismissedDiffEntries = dismissedDiffEntries
        self.dismissedStaleApps = dismissedStaleApps
        self.fileManager = fileManager
        self.defaults = defaults
        self.rescan = rescan
    }

    @discardableResult
    func reset() async -> ResetResult {
        await weeklyDigestCoordinator.scheduler.cancelAll(
            matchingPrefix: WeeklyDigestCoordinator.identifierPrefix
        )
        await weeklyDigestCoordinator.scheduler.cancelAll(
            matchingPrefix: WeeklyDigestCoordinator.testIdentifierPrefix
        )

        releaseSnapshotStore()
        do {
            try removeHistoryFiles()
        } catch {
            Self.logger.error(
                "Reset failed during database deletion: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(phase: .deleteHistory, message: error.localizedDescription)
        }

        resetLiveStores()
        clearPrefixedDefaults()

        do {
            try recreateHistory()
        } catch {
            Self.logger.error(
                "Failed to re-init snapshot store after reset: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(phase: .recreateHistory, message: error.localizedDescription)
        }

        clearPresentationState()
        let scanSucceeded = await rescan()
        await weeklyDigestCoordinator.reconcileSchedule()
        return .completed(scanSucceeded: scanSucceeded)
    }

    private func removeHistoryFiles() throws {
        let urls = [
            snapshotPathURL,
            URL(fileURLWithPath: snapshotPathURL.path + "-wal"),
            URL(fileURLWithPath: snapshotPathURL.path + "-shm"),
        ]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func resetLiveStores() {
        preferencesStore.resetToDefaults()
        dismissedDiffEntries.removeAll()
        dismissedStaleApps.removeAll()
    }

    private func clearPrefixedDefaults() {
        let keys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.bundlePrefix) }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private func recreateHistory() throws {
        let path = snapshotPathURL.path(percentEncoded: false)
        onSnapshotStoreReinit(try SnapshotStore(path: path))
    }

    private func clearPresentationState() {
        viewModel.grants.removeAll()
        viewModel.launchAgents.removeAll()
        viewModel.btmItems.removeAll()
        viewModel.tccScanError = nil
        viewModel.btmScanError = nil
        viewModel.launchAgentScanError = nil
        viewModel.latestSnapshotID = nil
        viewModel.lastReviewedSnapshotID = nil
        viewModel.latestDiffYesterday = nil
        viewModel.latestDiffWeek = nil
        viewModel.staleApps.removeAll()
        viewModel.pendingRoute = nil
        viewModel.lastScanDate = nil
        viewModel.staleThresholdDays = preferencesStore.staleThresholdDays
        viewModel.snapshotStoreUnavailable = false
        viewModel.diffUnavailable = false
    }
}
