import AppKit
import Foundation
import Testing
@testable import PermissionPulse

@Suite @MainActor struct ScanSchedulerTests {
    @MainActor private final class Harness {
        let workspace = NotificationCenter()
        let defaults = NotificationCenter()
        var lastScan: Date?
        var requests = 0
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        lazy var scheduler = ScanScheduler(
            workspaceCenter: workspace,
            defaultCenter: defaults,
            now: { [now] in now },
            lastScanDate: { [unowned self] in self.lastScan },
            requestScan: { [unowned self] in self.requests += 1 }
        )
    }

    @Test func wakeRequestsOneScan() {
        let h = Harness()
        h.scheduler.start()
        h.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(h.requests == 1)
    }

    @Test func dayChangeRequestsOneScan() {
        let h = Harness()
        h.scheduler.start()
        h.defaults.post(name: .NSCalendarDayChanged, object: nil)
        #expect(h.requests == 1)
    }

    @Test func startingTwiceDoesNotDoubleObservers() {
        let h = Harness()
        h.scheduler.start()
        h.scheduler.start()
        h.workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(h.requests == 1)
    }

    @Test func openingWithStaleScanRequestsOne() {
        let h = Harness()
        h.lastScan = h.now.addingTimeInterval(-2 * 60)
        h.scheduler.noteBecameVisible()
        #expect(h.requests == 1)
    }

    @Test func openingWithFreshScanRequestsNone() {
        let h = Harness()
        h.lastScan = h.now.addingTimeInterval(-30)
        h.scheduler.noteBecameVisible()
        #expect(h.requests == 0)
    }

    @Test func openingBeforeAnyScanRequestsOne() {
        let h = Harness()
        h.scheduler.noteBecameVisible()
        #expect(h.requests == 1)
    }
}
