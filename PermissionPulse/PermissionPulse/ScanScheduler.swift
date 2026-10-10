import AppKit // AppKit: NSWorkspace.didWakeNotification has no SwiftUI equivalent.
import Foundation
import OSLog

/// Decides *when* to scan; `AppDelegate.rescan()` stays the single *how*, and
/// its in-progress guard coalesces overlapping requests.
@MainActor
final class ScanScheduler {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "scan-scheduler"
    )

    /// A guess: frequent enough that opening the menu shows current state,
    /// rare enough that browsing doesn't rescan constantly. Retune from the
    /// `scan-coordinator` duration logs.
    static let staleScanInterval: TimeInterval = 15 * 60

    private let workspaceCenter: NotificationCenter
    private let defaultCenter: NotificationCenter
    private let now: () -> Date
    private let lastScanDate: () -> Date?
    private let requestScan: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        defaultCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        lastScanDate: @escaping () -> Date?,
        requestScan: @escaping () -> Void
    ) {
        self.workspaceCenter = workspaceCenter
        self.defaultCenter = defaultCenter
        self.now = now
        self.lastScanDate = lastScanDate
        self.requestScan = requestScan
    }

    func start() {
        guard observers.isEmpty else { return }
        observers.append(observe(NSWorkspace.didWakeNotification, on: workspaceCenter, reason: "wake"))
        observers.append(observe(.NSCalendarDayChanged, on: defaultCenter, reason: "new day"))
    }

    func stop() {
        observers.forEach { token in
            workspaceCenter.removeObserver(token)
            defaultCenter.removeObserver(token)
        }
        observers.removeAll()
    }

    /// Called when the dropdown or detail window appears.
    func noteBecameVisible() {
        if let last = lastScanDate(), now().timeIntervalSince(last) < Self.staleScanInterval {
            return
        }
        trigger(reason: "stale on open")
    }

    private func observe(
        _ name: Notification.Name,
        on center: NotificationCenter,
        reason: String
    ) -> NSObjectProtocol {
        // queue: .main delivers on the main thread whatever thread posted.
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.trigger(reason: reason) }
        }
    }

    private func trigger(reason: String) {
        Self.logger.info("Scan requested: \(reason, privacy: .public)")
        requestScan()
    }
}
