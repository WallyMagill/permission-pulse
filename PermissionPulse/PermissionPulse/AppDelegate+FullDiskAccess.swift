import AppKit
import Foundation
import PermissionsUI

/// Full Disk Access turned off after it worked: say why, once per version,
/// and close the loop when the user comes back from System Settings.
extension AppDelegate {
    static let lastLaunchedVersionKey = "com.wallymagill.permissionpulse.lastLaunchedVersion"
    static let fdaPromptShownForVersionKey = "com.wallymagill.permissionpulse.fdaPromptShownForVersion"

    /// Runs after a scan and before its snapshot is written, so "captured
    /// before" can only mean an earlier snapshot. Records this build as the
    /// last launched one afterwards, but only when history could answer:
    /// without it a later loss after an update would read as revoked.
    func classifyFullDiskAccessLoss() async -> FullDiskAccessLoss? {
        guard let snapshotCoordinator else { return nil }
        let running = appVersion.identifier
        let lastLaunched = runtimeDefaults.string(forKey: Self.lastLaunchedVersionKey)
        guard FullDiskAccessLoss.isDenied(tcc: viewModel.tccAvailability) else {
            runtimeDefaults.set(running, forKey: Self.lastLaunchedVersionKey)
            return nil
        }
        guard let capturedBefore = await snapshotCoordinator.hasCapturedProtectedData() else {
            return nil
        }
        runtimeDefaults.set(running, forKey: Self.lastLaunchedVersionKey)
        return FullDiskAccessLoss.classify(
            capturedBefore: capturedBefore,
            lastLaunchedVersion: lastLaunched,
            runningVersion: running
        )
    }

    /// Opens the recovery window and, with change alerts on, notifies — at
    /// most once per version.
    func handleFullDiskAccessLoss(_ loss: FullDiskAccessLoss?) async {
        guard let loss, loss.opensRecoveryWindow else { return }
        let version = appVersion.identifier
        guard runtimeDefaults.string(forKey: Self.fdaPromptShownForVersionKey) != version else { return }
        runtimeDefaults.set(version, forKey: Self.fdaPromptShownForVersionKey)
        presentFullDiskAccessRecovery(loss)
        await changeAlertCoordinator.fullDiskAccessTurnedOff()
    }

    /// A click on the "Full Disk Access was turned off" notification. Access
    /// may be back since it was posted, and the recovery window would then
    /// wait for a change that already happened, so it opens only while the
    /// permissions scan is denied.
    func openFullDiskAccessNotification() {
        guard FullDiskAccessLoss.isDenied(tcc: viewModel.tccAvailability) else {
            showDetailWindow(route: .overview)
            return
        }
        presentFullDiskAccessRecovery(lastFullDiskAccessLoss ?? .revoked)
    }

    private func presentFullDiskAccessRecovery(_ loss: FullDiskAccessLoss) {
        lastFullDiskAccessLoss = loss
        if let fullDiskAccessPromptPresenter {
            fullDiskAccessPromptPresenter(loss)
        } else {
            showFullDiskAccessWindow(loss)
        }
    }

    /// Called when the app becomes active: if a recovery window is waiting
    /// and the user just came back, scan again (or wait for the scan already
    /// running) and report the result.
    func recheckFullDiskAccessIfReturning() async {
        guard fullDiskAccessRecovery.shouldRecheckOnActivation(), resetTask == nil else { return }
        fullDiskAccessRecovery.phase = .checking
        let scanned: Bool
        if let scanTask {
            scanned = await scanTask.value
        } else {
            scanned = await performRescanIfIdle()
        }
        guard fullDiskAccessRecovery.phase == .checking else { return }
        fullDiskAccessRecovery.phase = scanned
            ? FullDiskAccessRecovery.outcome(tcc: viewModel.tccAvailability)
            : .waiting
    }

    // AppKit: a one-shot window opened from the delegate, which has no
    // SwiftUI openWindow, and must not depend on the menu-bar icon.
    func showFullDiskAccessWindow(_ loss: FullDiskAccessLoss) {
        lastFullDiskAccessLoss = loss
        fullDiskAccessRecovery.beginWaiting()
        if let fullDiskAccessWindow {
            WindowActivation.bringToFront(fullDiskAccessWindow)
            return
        }
        let view = FullDiskAccessPromptView(
            loss: loss,
            bundlePath: AppLocation.displayPath(Bundle.main.bundlePath),
            recovery: fullDiskAccessRecovery,
            onClose: { [weak self] in self?.fullDiskAccessWindow?.close() }
        )
        fullDiskAccessWindow = presentWindow(
            title: String(localized: "Full Disk Access"),
            size: NSSize(width: 480, height: 460),
            rootView: view
        )
    }
}
