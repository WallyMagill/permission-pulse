import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ResetAllDataServiceTests {
    @Test func removesSnapshotsDBAndReInitsStore() async throws {
        let env = try Environment()

        try Data("seed".utf8).write(to: env.dbURL)
        #expect(FileManager.default.fileExists(atPath: env.dbURL.path))

        await env.service.reset()

        // SnapshotStore init re-creates the file (empty SQLite).
        #expect(FileManager.default.fileExists(atPath: env.dbURL.path))
        #expect(env.counter.reinitCount == 1)
    }

    @Test func removesAllPPDefaultsKeysPreservingNonPPKeys() async throws {
        let env = try Environment()
        env.defaults.set("a", forKey: "com.wallymagill.permissionpulse.hasSeenWelcome")
        env.defaults.set("b", forKey: "com.wallymagill.permissionpulse.lastSnapshotDate")
        env.defaults.set("preserve", forKey: "NSWindow Frame detail-AppWindow-1")
        env.defaults.set("preserve", forKey: "NSStatusItem Preferred Position Item-0")

        await env.service.reset()

        #expect(env.defaults.object(forKey: "com.wallymagill.permissionpulse.hasSeenWelcome") == nil)
        #expect(env.defaults.object(forKey: "com.wallymagill.permissionpulse.lastSnapshotDate") == nil)
        #expect(env.defaults.string(forKey: "NSWindow Frame detail-AppWindow-1") == "preserve")
        #expect(env.defaults.string(forKey: "NSStatusItem Preferred Position Item-0") == "preserve")
    }

    @Test func cancelsPendingDigestNotifications() async throws {
        let env = try Environment()
        try await env.scheduler.scheduleWeekly(
            identifier: WeeklyDigestCoordinator.weeklyIdentifier,
            weekday: 2, hour: 9, minute: 0,
            title: "T", body: "B"
        )
        let beforePending = await env.scheduler.pendingIdentifiers()
        #expect(beforePending.count == 1)

        await env.service.reset()

        let afterPending = await env.scheduler.pendingIdentifiers()
        #expect(afterPending.isEmpty)
    }

    @Test func resetReportsReinitSuccess() async throws {
        let env = try Environment()
        let succeeded = await env.service.reset()
        #expect(succeeded == true)
    }

    @Test func idempotentOnSecondCallWithEmptyState() async throws {
        let env = try Environment()
        await env.service.reset() // clean state
        await env.service.reset() // should not throw / no-op
        #expect(env.counter.reinitCount == 2, "Re-init runs each call even when DB absent")
    }

    @Test func resetReportsFailureWhenStoreCannotReinit() async throws {
        // Make the parent of the snapshot path a regular file so SnapshotStore
        // re-init must fail (you can't create a file inside a file).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pp-reset-fail-\(UUID().uuidString)")
        try Data().write(to: tmp)                       // `tmp` is now a regular FILE
        defer { try? FileManager.default.removeItem(at: tmp) }
        let badPath = tmp.appendingPathComponent("snapshots.db")  // parent is a file

        var reinitCalled = false
        let env = try Environment()
        let service = ResetAllDataService(
            viewModel: env.viewModel,
            snapshotPathURL: badPath,
            onSnapshotStoreReinit: { _ in reinitCalled = true },
            weeklyDigestCoordinator: env.weeklyDigestCoordinator,
            defaults: env.defaults,
            rescan: { }
        )
        let ok = await service.reset()
        #expect(ok == false)
        #expect(reinitCalled == false)
    }

    // MARK: - Env

    @MainActor
    final class ReinitCounter {
        var reinitCount: Int = 0
    }

    @MainActor
    final class Environment {
        let viewModel: AppViewModel
        let preferencesStore: PreferencesStore
        let scheduler: MockWeeklyDigestScheduler
        let weeklyDigestCoordinator: WeeklyDigestCoordinator
        let defaults: UserDefaults
        let dbURL: URL
        let counter = ReinitCounter()
        let service: ResetAllDataService

        init() throws {
            self.viewModel = AppViewModel()
            self.defaults = UserDefaults(suiteName: "reset-test-\(UUID().uuidString)")!
            self.preferencesStore = PreferencesStore(defaults: defaults)
            self.scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
            self.weeklyDigestCoordinator = WeeklyDigestCoordinator(
                viewModel: viewModel,
                preferencesStore: preferencesStore,
                scheduler: scheduler
            )

            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("reset-svc-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.dbURL = dir.appendingPathComponent("snapshots.db")

            let counterRef = counter
            self.service = ResetAllDataService(
                viewModel: viewModel,
                snapshotPathURL: dbURL,
                onSnapshotStoreReinit: { _ in counterRef.reinitCount += 1 },
                weeklyDigestCoordinator: weeklyDigestCoordinator,
                defaults: defaults,
                rescan: { }
            )
        }
    }
}
