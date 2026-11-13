import Foundation
import GRDB
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

/// Per-domain baselines, the since-last-review window, review marking,
/// shared change counts, and visible failures.
@Suite @MainActor struct SnapshotHistoryTests {
    private typealias Environment = SnapshotCoordinatorTests.Environment
    private let day: TimeInterval = 86_400

    // A launch without Full Disk Access writes a snapshot with Permissions
    // failed; when it is the last one before the cutoff it must not block
    // comparing Permissions against the capture before it.
    @Test func failedSnapshotAtTheCutoffNoLongerBlocksComparison() async throws {
        let env = try await Environment(now: historyNow)
        let lastCapture = try await env.store.writeFullSnapshot(
            grants: [grant("com.example.a")], launchAgents: [], btmItems: [],
            at: historyNow().addingTimeInterval(-3 * day)
        )
        _ = try await env.store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [],
            coverage: SnapshotDomainCoverage(tcc: .failed, btm: .failed, launchAgents: .complete),
            at: historyNow().addingTimeInterval(-1 * day)
        )
        env.viewModel.grants = [grant("com.example.a"), grant("com.example.b")]

        await env.coordinator.onScanCompleted()

        let diff = try #require(env.viewModel.latestDiffSinceReview)
        #expect(diff.uncomparedDomains.isEmpty)
        #expect(diff.tcc.added.map(\.app.bundleID) == ["com.example.b"])
        #expect(diff.baselines[.tcc]?.id == lastCapture)
    }

    @Test func firstWindowComparesWithTheLastReviewedSnapshot() async throws {
        let env = try await Environment(now: historyNow)
        _ = try await env.store.writeFullSnapshot(
            grants: [grant("com.example.a")], launchAgents: [], btmItems: [],
            at: historyNow().addingTimeInterval(-3 * day)
        )
        let reviewed = try await env.store.writeFullSnapshot(
            grants: [grant("com.example.a"), grant("com.example.b")], launchAgents: [], btmItems: [],
            at: historyNow().addingTimeInterval(-2 * day)
        )
        env.defaults.set(reviewed.rawValue, forKey: SnapshotCoordinator.lastReviewedSnapshotIDKey)
        env.viewModel.grants = [grant("com.example.a"), grant("com.example.b"), grant("com.example.c")]

        await env.coordinator.onScanCompleted()

        let diff = try #require(env.viewModel.latestDiffSinceReview)
        #expect(diff.tcc.added.map(\.app.bundleID) == ["com.example.c"])
        #expect(diff.reviewedSnapshotID == reviewed)
        #expect(diff.baselines[.tcc] == DiffBaseline(id: reviewed, date: historyNow().addingTimeInterval(-2 * day)))
    }

    @Test func missingReviewedSnapshotFallsBackToTheStartOfToday() async throws {
        let env = try await Environment(now: historyNow)
        let pruned = try await env.store.writeFullSnapshot(
            grants: [], launchAgents: [], btmItems: [], at: historyNow().addingTimeInterval(-30 * day)
        )
        for daysAgo in [20.0, 1] {
            _ = try await env.store.writeFullSnapshot(
                grants: [grant("com.example.a")], launchAgents: [], btmItems: [],
                at: historyNow().addingTimeInterval(-daysAgo * day)
            )
        }
        try await env.store.pruneSnapshots(olderThan: historyNow().addingTimeInterval(-5 * day))
        #expect(try await env.store.snapshotSummary(id: pruned) == nil)
        env.defaults.set(pruned.rawValue, forKey: SnapshotCoordinator.lastReviewedSnapshotIDKey)
        env.viewModel.grants = [grant("com.example.a"), grant("com.example.b")]

        await env.coordinator.onScanCompleted()

        let diff = try #require(env.viewModel.latestDiffSinceReview)
        #expect(diff.reviewedSnapshotID == nil)
        #expect(diff.tcc.added.map(\.app.bundleID) == ["com.example.b"])
    }

    @Test func markingReviewedEmptiesTheFirstWindowAndTheBadge() async throws {
        let env = try await Environment(now: historyNow)
        _ = try await env.store.writeFullSnapshot(
            grants: [], launchAgents: [], btmItems: [], at: historyNow().addingTimeInterval(-8 * day)
        )
        env.viewModel.grants = [grant("com.example.new")]
        await env.coordinator.onScanCompleted()
        #expect(env.viewModel.unreviewedChangeCount == 1)

        await env.coordinator.markCurrentSnapshotReviewed()?.value

        #expect(env.viewModel.latestDiffSinceReview?.hasContent == false)
        #expect(env.viewModel.unreviewedChangeCount == 0)
        #expect(env.viewModel.latestDiffWeek?.hasContent == true)
    }

    @Test func coverageOnlySnapshotRaisesNoBadge() async throws {
        let env = try await Environment(now: historyNow)
        env.viewModel.grants = [grant("com.example.a")]
        await env.coordinator.onScanCompleted()
        await env.coordinator.markCurrentSnapshotReviewed()?.value
        env.viewModel.launchAgentAvailability = .degraded(
            lastUpdated: historyNow(),
            warnings: [ScannerWarning(source: .entries, omittedCount: 1)]
        )

        await env.coordinator.onScanCompleted()

        #expect(try await env.snapshotsCount() == 2)
        #expect(env.viewModel.latestDiffSinceReview?.uncomparedDomains == [.launchAgents])
        #expect(!env.viewModel.hasUnreviewedChanges)
    }

    // On real data: snapshot 5 (macOS 26, complete) and snapshot 8 (macOS 27,
    // reduced) hold the same 52 system-level grants.
    @Test func upgradeToReducedScopeComparesSystemLevelPermissions() async throws {
        let env = try await Environment(now: historyNow)
        _ = try await env.store.writeFullSnapshot(
            grants: [grant("com.example.ax", service: .accessibility), grant("com.example.mic")],
            launchAgents: [], btmItems: [], at: historyNow().addingTimeInterval(-2 * day)
        )
        env.viewModel.tccUnavailableSources = [.userTCCDatabase]
        env.viewModel.grants = [
            grant("com.example.ax", service: .accessibility),
            grant("com.example.rec", service: .screenRecording),
        ]

        await env.coordinator.onScanCompleted()

        let diff = try #require(env.viewModel.latestDiffSinceReview)
        #expect(diff.systemLevelPermissionsOnly)
        #expect(diff.uncomparedDomains.isEmpty)
        #expect(diff.tcc.added.map(\.app.bundleID) == ["com.example.rec"])
        #expect(diff.tcc.removed.isEmpty)
    }

    @Test func failedSnapshotWriteIsFlagged() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pp-write-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SnapshotStore(path: url.path(percentEncoded: false))
        try await DatabaseQueue(path: url.path(percentEncoded: false)).write { db in
            try db.execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON snapshots BEGIN SELECT RAISE(ABORT, 'test'); END")
        }
        let viewModel = AppViewModel(tccAvailability: .complete(lastUpdated: historyNow()))
        viewModel.grants = [grant("com.example.a")]
        let coordinator = SnapshotCoordinator(
            viewModel: viewModel, store: store,
            defaults: UserDefaults(suiteName: "write-fail-\(UUID().uuidString)")!, now: historyNow
        )

        await coordinator.onScanCompleted()

        #expect(viewModel.snapshotWriteFailed)
        #expect(viewModel.latestSnapshotID == nil)
    }

    @Test func refreshDropsExpiredSnoozes() async throws {
        let env = try await Environment(now: historyNow)
        let dismissed = DismissedDiffEntryStore(defaults: env.defaults)
        dismissed.snooze(key: "expired", until: historyNow().addingTimeInterval(-60))
        dismissed.snooze(key: "active", until: historyNow().addingTimeInterval(60))
        env.viewModel.dismissedDiffEntries = dismissed
        env.viewModel.grants = [grant("com.example.a")]

        await env.coordinator.onScanCompleted()

        #expect(Set(dismissed.allEntries().keys) == ["active"])
    }

    @Test func firstSnapshotIsTheBaselineForLaterChanges() async throws {
        let env = try await Environment(now: historyNow)
        env.viewModel.grants = [grant("com.example.a")]
        await env.coordinator.onScanCompleted()
        let first = try #require(env.viewModel.latestSnapshotID)
        #expect(env.viewModel.lastReviewedSnapshotID == first)
        #expect(env.defaults.object(forKey: SnapshotCoordinator.lastReviewedSnapshotIDKey) as? Int64 == first.rawValue)

        env.viewModel.grants.append(grant("com.example.b"))
        await env.coordinator.onScanCompleted()

        let diff = try #require(env.viewModel.latestDiffSinceReview)
        #expect(diff.tcc.added.map(\.app.bundleID) == ["com.example.b"])
        #expect(env.viewModel.unreviewedChangeCount == 1)
    }

    @Test func writeHookReportsThePreviousAndNewSnapshot() async throws {
        let env = try await Environment(now: historyNow)
        var calls: [(SnapshotID?, SnapshotID)] = []
        env.coordinator.onSnapshotWritten = { calls.append(($0, $1)) }
        env.viewModel.grants = [grant("com.example.a")]
        await env.coordinator.onScanCompleted()
        env.viewModel.grants.append(grant("com.example.b"))
        await env.coordinator.onScanCompleted()
        await env.coordinator.onScanCompleted()

        #expect(calls.map { $0.0 } == [nil, SnapshotID(rawValue: 1)])
        #expect(calls.map { $0.1 } == [SnapshotID(rawValue: 1), SnapshotID(rawValue: 2)])
    }

    @Test func pruningKeepsTheLastReviewedSnapshot() async throws {
        let env = try await Environment(now: historyNow, snapshotRetentionDays: 10)
        let reviewed = try await env.store.writeFullSnapshot(
            grants: [], launchAgents: [], btmItems: [], at: historyNow().addingTimeInterval(-30 * day)
        )
        _ = try await env.store.writeFullSnapshot(
            grants: [grant("com.example.a")], launchAgents: [], btmItems: [],
            at: historyNow().addingTimeInterval(-20 * day)
        )
        env.defaults.set(reviewed.rawValue, forKey: SnapshotCoordinator.lastReviewedSnapshotIDKey)
        env.viewModel.grants = [grant("com.example.b")]

        await env.coordinator.onScanCompleted()

        #expect(try await env.store.snapshotSummary(id: reviewed) != nil)
        #expect(env.viewModel.latestDiffSinceReview?.tcc.added.map(\.app.bundleID) == ["com.example.b"])
    }
}

@Sendable
private func historyNow() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

private func grant(_ bundleID: String, service: PermissionService = .microphone) -> PermissionGrant {
    PermissionGrant(
        service: service,
        app: AppIdentity(bundleID: bundleID, displayName: bundleID),
        lastModified: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
