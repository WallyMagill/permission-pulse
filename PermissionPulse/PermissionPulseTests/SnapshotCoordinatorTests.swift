import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct SnapshotCoordinatorTests {
    @Test func skipsWriteWhenSentinelMatchesToday() async throws {
        let env = try await Environment(now: fixedNow)
        // Mark today as already written.
        env.defaults.set(
            ISO8601DateFormatter().string(from: fixedNow()),
            forKey: SnapshotCoordinator.lastSnapshotDateKey
        )

        // Also write one snapshot directly so latestSnapshotID returns non-nil
        // for the refresh path.
        _ = try await env.store.writeFullSnapshot(
            grants: [], launchAgents: [], btmItems: [], at: fixedNow()
        )
        let beforeCount = try await env.snapshotsCount()

        env.viewModel.grants = [demoGrant()]
        await env.coordinator.onScanCompleted()

        let afterCount = try await env.snapshotsCount()
        #expect(afterCount == beforeCount, "Should not have written another snapshot")
    }

    @Test func writesAfterSuccessfulScanWhenSentinelStale() async throws {
        let env = try await Environment(now: fixedNow)
        let beforeCount = try await env.snapshotsCount()
        env.viewModel.grants = [demoGrant()]
        env.viewModel.launchAgents = [demoLaunchAgent()]

        await env.coordinator.onScanCompleted()

        let afterCount = try await env.snapshotsCount()
        #expect(afterCount == beforeCount + 1)
        #expect(env.viewModel.latestSnapshotID != nil)
    }

    @Test func skipsWriteWhenAnyScannerErrored() async throws {
        let env = try await Environment(now: fixedNow)
        env.viewModel.tccScanError = .permissionDenied(reason: "FDA needed")
        env.viewModel.grants = [demoGrant()]

        let beforeCount = try await env.snapshotsCount()
        await env.coordinator.onScanCompleted()
        let afterCount = try await env.snapshotsCount()

        #expect(afterCount == beforeCount)
        #expect(env.viewModel.latestSnapshotID == nil)
    }

    @Test func pushesDiffsAndStaleAppsToViewModelAfterWrite() async throws {
        // Seed an older snapshot (~36 hours ago) so the yesterday window has
        // something to diff against the new write.
        let staleBundlePath = URL(fileURLWithPath: "/Applications/StaleApp.app")
        let oldUsedDate = Date(timeIntervalSince1970: fixedNow().timeIntervalSince1970 - 200 * 86_400)
        let mock = MockLastUsedProbe(fixed: [staleBundlePath: (oldUsedDate, .spotlight)])
        let env = try await Environment(now: fixedNow, probe: mock)

        let yesterdayGrant = demoGrant(bundleID: "com.example.oldOnly")
        _ = try await env.store.writeFullSnapshot(
            grants: [yesterdayGrant],
            launchAgents: [],
            btmItems: [],
            at: fixedNow().addingTimeInterval(-36 * 60 * 60)
        )

        env.viewModel.grants = [
            demoGrant(bundleID: "com.example.staleApp", bundlePath: staleBundlePath),
        ]
        await env.coordinator.onScanCompleted()

        // Yesterday diff should be non-nil with content (oldOnly was removed,
        // staleApp was added).
        let yd = env.viewModel.latestDiffYesterday
        #expect(yd != nil)
        #expect(yd?.hasContent == true)
        // Stale apps should include the one app whose probe date is 200d old.
        #expect(env.viewModel.staleApps.contains { $0.app.bundleID == "com.example.staleApp" })
    }

    @Test func markCurrentSnapshotReviewedClearsBadge() async throws {
        let env = try await Environment(now: fixedNow)
        // Force a state where hasUnreviewedChanges == true.
        env.viewModel.latestSnapshotID = SnapshotID(rawValue: 1)
        env.viewModel.lastReviewedSnapshotID = nil
        env.viewModel.latestDiffYesterday = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 0),
            toID: SnapshotID(rawValue: 1),
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [demoLaunchAgent()], removed: [])
        )
        #expect(env.viewModel.hasUnreviewedChanges)

        env.coordinator.markCurrentSnapshotReviewed()

        #expect(env.viewModel.lastReviewedSnapshotID == SnapshotID(rawValue: 1))
        #expect(!env.viewModel.hasUnreviewedChanges)
        // Persisted to defaults.
        let stored = env.defaults.object(forKey: SnapshotCoordinator.lastReviewedSnapshotIDKey) as? Int64
        #expect(stored == 1)
    }

    // MARK: - Helpers

    @MainActor
    final class Environment {
        let store: SnapshotStore
        let viewModel: AppViewModel
        let defaults: UserDefaults
        let coordinator: SnapshotCoordinator

        init(
            now: @Sendable @escaping () -> Date,
            probe: any LastUsedProbe = MockLastUsedProbe()
        ) async throws {
            self.store = try SnapshotStore.inMemory()
            self.viewModel = AppViewModel()
            self.defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
            self.coordinator = SnapshotCoordinator(
                viewModel: viewModel,
                store: store,
                lastUsedProbe: probe,
                defaults: defaults,
                calendar: Calendar(identifier: .gregorian),
                now: now
            )
        }

        // Returns the highest snapshot rowid (auto-increment starts at 1), which
        // for a freshly-created in-memory store doubles as a snapshot count.
        func snapshotsCount() async throws -> Int {
            guard let latest = try await store.latestSnapshotID() else { return 0 }
            return Int(latest.rawValue)
        }
    }
}

@Sendable
private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

private func demoGrant(
    bundleID: String = "com.example.demo",
    bundlePath: URL? = nil
) -> PermissionGrant {
    PermissionGrant(
        service: .microphone,
        app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: bundlePath),
        lastModified: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func demoLaunchAgent(label: String = "com.example.demo") -> LaunchAgentItem {
    LaunchAgentItem(
        label: label,
        sourceDirectory: .userLaunchAgents,
        programPath: "/usr/local/bin/demo",
        programArguments: [],
        runAtLoad: true,
        keepAlive: false
    )
}
