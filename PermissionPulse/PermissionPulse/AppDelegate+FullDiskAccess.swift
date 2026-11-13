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
    /// last launched one afterwards.
    func classifyFullDiskAccessLoss() async -> FullDiskAccessLoss? {
        let running = appVersion.identifier
        let lastLaunched = runtimeDefaults.string(forKey: Self.lastLaunchedVersionKey)
        defer { runtimeDefaults.set(running, forKey: Self.lastLaunchedVersionKey) }
        guard FullDiskAccessLoss.isDenied(
            tcc: viewModel.tccAvailability,
            btm: viewModel.btmAvailability
        ) else { return nil }
        let capturedBefore = await snapshotCoordinator?.hasCapturedProtectedData() ?? false
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
        if let fullDiskAccessPromptPresenter {
            fullDiskAccessPromptPresenter(loss)
        } else {
            showFullDiskAccessWindow(loss)
        }
        await changeAlertCoordinator.fullDiskAccessTurnedOff()
    }

    /// Called when the app becomes active: if a recovery window is waiting
    /// and the user just came back, scan again and report the result.
    func recheckFullDiskAccessIfReturning() async {
        guard fullDiskAccessRecovery.shouldRecheckOnActivation(), resetTask == nil else { return }
        fullDiskAccessRecovery.phase = .checking
        let scanned = await performRescanIfIdle()
        guard fullDiskAccessRecovery.phase == .checking else { return }
        fullDiskAccessRecovery.phase = scanned
            ? FullDiskAccessRecovery.outcome(tcc: viewModel.tccAvailability, btm: viewModel.btmAvailability)
            : .waiting
    }

    // AppKit: a one-shot window opened from the delegate, which has no
    // SwiftUI openWindow, and must not depend on the menu-bar icon.
    func showFullDiskAccessWindow(_ loss: FullDiskAccessLoss) {
        fullDiskAccessRecovery.beginWaiting()
        if let fullDiskAccessWindow {
            fullDiskAccessWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
