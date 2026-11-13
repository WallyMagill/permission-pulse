import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ScanCompletionTests {
    @Test func scanThatChangesTheWeekDiffRefreshesThePendingDigestBody() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-completion-digest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(
            path: directory.appendingPathComponent("snapshots.db").path(percentEncoded: false)
        )
        // An empty, fully captured snapshot from before the 7-day cutoff is
        // the week baseline the scan's mock results are compared against.
        _ = try await store.writeSnapshot(
            grants: [],
            launchAgents: [],
            btmItems: [],
            coverage: .allComplete,
            at: Date().addingTimeInterval(-9 * 86_400)
        )
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(environment: ["PERMISSION_PULSE_TEST_MODE": "1"]),
            weeklyDigestScheduler: scheduler
        )
        defer { UserDefaults().removePersistentDomain(forName: AppDelegate.testDefaultsSuiteName) }
        delegate.installSnapshotRuntime(store)
        delegate.preferencesStore.digestEnabled = true
        _ = await delegate.weeklyDigestCoordinator.reconcileSchedule()
        let before = await scheduler.lastScheduledWeeklyBody()

        await delegate.rescan()

        let after = await scheduler.lastScheduledWeeklyBody()
        #expect(before == "History is less than a week old, so there's nothing to compare yet.")
        #expect(after != before)
        #expect(after?.hasSuffix("in the last week.") == true)
        #expect(await scheduler.pendingIdentifiers() == [WeeklyDigestCoordinator.weeklyIdentifier])
    }
}

extension MockWeeklyDigestScheduler {
    func lastScheduledWeeklyBody() -> String? {
        recorded.reversed().lazy.compactMap { action -> String? in
            guard case .scheduled(_, _, _, _, _, let body) = action else { return nil }
            return body
        }.first
    }
}
