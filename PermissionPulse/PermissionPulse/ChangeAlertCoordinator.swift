import Foundation
import OSLog
import PermissionsCore
import PermissionsUI

/// Posts the opt-in "something changed" notification after a scan writes a
/// snapshot, and the one-per-version "Full Disk Access was turned off" one.
@MainActor
final class ChangeAlertCoordinator {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "change-alerts"
    )

    static let identifierPrefix = "com.wallymagill.permissionpulse.changes."
    /// Fixed, so a newer alert replaces an older one instead of stacking.
    static let changesIdentifier = "\(identifierPrefix)latest"
    static let fullDiskAccessIdentifier = "\(identifierPrefix)full-disk-access"
    /// The shortest delay `UNTimeIntervalNotificationTrigger` accepts.
    static let deliveryDelay: TimeInterval = 1

    private let viewModel: AppViewModel
    private let preferencesStore: PreferencesStore
    private let scheduler: any WeeklyDigestScheduler
    private let now: @Sendable () -> Date

    init(
        viewModel: AppViewModel,
        preferencesStore: PreferencesStore,
        scheduler: any WeeklyDigestScheduler,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.viewModel = viewModel
        self.preferencesStore = preferencesStore
        self.scheduler = scheduler
        self.now = now
    }

    func handleToggle(turnOn: Bool) async -> PreferencesViewModel.ChangeAlertsHint {
        guard turnOn else {
            await scheduler.cancelAll(matchingPrefix: Self.identifierPrefix)
            return .off
        }
        switch await NotificationAuthorization.ensure(using: scheduler) {
        case .authorized: return .on
        case .denied: return .denied
        case .failed(let message): return .failed(message)
        }
    }

    /// `changes` is the diff from the previous snapshot to the one just
    /// written; nil on the first snapshot ever, so nothing is posted then.
    func snapshotWritten(changes: SnapshotDiffs?) async {
        guard preferencesStore.changeAlertsEnabled,
              let alert = ChangeAlert.make(
                  for: changes,
                  dismissals: viewModel.dismissedDiffEntries,
                  asOf: now()
              ) else { return }
        await post(identifier: Self.changesIdentifier, title: alert.title, body: alert.body)
    }

    func fullDiskAccessTurnedOff() async {
        guard preferencesStore.changeAlertsEnabled else { return }
        await post(
            identifier: Self.fullDiskAccessIdentifier,
            title: String(localized: "Permission Pulse"),
            body: String(localized: "Full Disk Access was turned off. Open Permission Pulse to turn it back on.")
        )
    }

    private func post(identifier: String, title: String, body: String) async {
        guard await NotificationAuthorization.isAuthorized(using: scheduler) else {
            Self.logger.info("Change alert skipped — notifications are not authorized")
            return
        }
        do {
            try await scheduler.scheduleOneShot(
                identifier: identifier,
                after: Self.deliveryDelay,
                title: title,
                body: body
            )
        } catch {
            Self.logger.error("Change alert failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
