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

@MainActor
protocol ResetFileManaging: Sendable {
    func removeItem(at url: URL) throws
}

extension FileManager: ResetFileManaging {}

@MainActor
protocol ResetDefaultsManaging: Sendable {
    func resetKeys() -> [String]
    func removeResetValue(forKey key: String) throws
    func containsResetValue(forKey key: String) -> Bool
}

extension UserDefaults: ResetDefaultsManaging {
    func resetKeys() -> [String] {
        Array(dictionaryRepresentation().keys)
    }

    func removeResetValue(forKey key: String) throws {
        removeObject(forKey: key)
    }

    func containsResetValue(forKey key: String) -> Bool {
        object(forKey: key) != nil
    }
}

private struct ResetDefaultsVerificationError: LocalizedError {
    let key: String

    var errorDescription: String? {
        String(localized: "Could not clear reset preference \(key).")
    }
}

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
    private let defaults: any ResetDefaultsManaging
    private let rescan: @MainActor () async -> Bool
    private var resetInProgress = false

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
        defaults: any ResetDefaultsManaging = UserDefaults.standard,
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
        guard !resetInProgress else {
            return .failed(
                phase: .cancelNotifications,
                message: String(localized: "Reset All Data is already in progress.")
            )
        }
        resetInProgress = true
        defer { resetInProgress = false }

        await weeklyDigestCoordinator.cancelWeeklySchedule()
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
        do {
            try clearPrefixedDefaults()
        } catch {
            Self.logger.error(
                "Reset failed while clearing preferences: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(phase: .clearDefaults, message: error.localizedDescription)
        }

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
        _ = await weeklyDigestCoordinator.reconcileSchedule()
        return .completed(scanSucceeded: scanSucceeded)
    }

    private func removeHistoryFiles() throws {
        let urls = [
            snapshotPathURL,
            URL(fileURLWithPath: snapshotPathURL.path + "-wal"),
            URL(fileURLWithPath: snapshotPathURL.path + "-shm"),
        ]
        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch where Self.isNoSuchFileError(error) {
                continue
            }
        }
    }

    private static func isNoSuchFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }

    private func resetLiveStores() {
        preferencesStore.resetToDefaults()
        dismissedDiffEntries.removeAll()
        dismissedStaleApps.removeAll()
    }

    private func clearPrefixedDefaults() throws {
        let keys = defaults.resetKeys()
            .filter { $0.hasPrefix(Self.bundlePrefix) }
        for key in keys {
            try defaults.removeResetValue(forKey: key)
        }
        for key in keys where defaults.containsResetValue(forKey: key) {
            throw ResetDefaultsVerificationError(key: key)
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
