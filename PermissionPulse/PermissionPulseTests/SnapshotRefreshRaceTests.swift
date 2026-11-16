import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

/// Mark as Reviewed and a scan both refresh the diffs. A review refresh
/// computed for an older latest snapshot that finishes last must not
/// overwrite the scan's newer diffs.
@Suite @MainActor struct SnapshotRefreshRaceTests {
    @Test func staleReviewRefreshFinishingLastIsDropped() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = SuspendingSnapshotStore(base: try SnapshotStore.inMemory())
        let viewModel = AppViewModel(
            tccAvailability: .complete(lastUpdated: now),
            btmAvailability: .complete(lastUpdated: now),
            launchAgentAvailability: .complete(lastUpdated: now)
        )
        let coordinator = SnapshotCoordinator(
            viewModel: viewModel,
            store: store,
            lastUsedProbe: MockLastUsedProbe(),
            defaults: UserDefaults(suiteName: "refresh-race-\(UUID().uuidString)")!,
            now: { now }
        )
        _ = try await store.base.writeFullSnapshot(
            grants: [grant("com.example.a")], launchAgents: [], btmItems: [],
            at: now.addingTimeInterval(-36 * 60 * 60)
        )
        viewModel.grants = [grant("com.example.a"), grant("com.example.b")]
        await coordinator.onScanCompleted()
        let reviewed = try #require(viewModel.latestSnapshotID)

        await store.gate.suspendNextSummary()
        let review = coordinator.markCurrentSnapshotReviewed()
        await store.gate.waitUntilSuspended()
        viewModel.grants.append(grant("com.example.c"))
        await coordinator.onScanCompleted()
        let latest = try #require(viewModel.latestSnapshotID)
        await store.gate.resume()
        await review?.value

        #expect(latest != reviewed)
        #expect(viewModel.latestSnapshotID == latest)
        #expect(viewModel.latestDiffSinceReview?.toID == latest)
        #expect(viewModel.latestDiffSinceReview?.tcc.added.map(\.app.bundleID) == ["com.example.c"])
        #expect(viewModel.hasUnreviewedChanges)
    }

    private func grant(_ bundleID: String) -> PermissionGrant {
        PermissionGrant(
            service: .microphone,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID),
            lastModified: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

/// Holds the next `snapshotSummary(id:)` call open until resumed.
private actor SummaryGate {
    private var armed = false
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspendNextSummary() { armed = true }

    func pass() async {
        guard armed else { return }
        armed = false
        await withCheckedContinuation { continuation in
            held = continuation
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilSuspended() async {
        guard held == nil else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume() {
        held?.resume()
        held = nil
    }
}

private struct SuspendingSnapshotStore: SnapshotHistoryStore {
    let base: SnapshotStore
    let gate = SummaryGate()

    func latestSnapshotID() async throws -> SnapshotID? { try await base.latestSnapshotID() }

    func snapshotSummary(id: SnapshotID) async throws -> SnapshotSummary? {
        await gate.pass()
        return try await base.snapshotSummary(id: id)
    }

    func snapshotSummaries(atOrBefore cutoff: Date) async throws -> [SnapshotSummary] {
        try await base.snapshotSummaries(atOrBefore: cutoff)
    }

    func evidenceChanged(
        since snapshotID: SnapshotID, grants: [PermissionGrant], launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem], coverage: SnapshotDomainCoverage
    ) async throws -> Bool {
        try await base.evidenceChanged(
            since: snapshotID, grants: grants, launchAgents: launchAgents, btmItems: btmItems, coverage: coverage
        )
    }

    func writeSnapshot(
        grants: [PermissionGrant], launchAgents: [LaunchAgentItem], btmItems: [BTMItem],
        coverage: SnapshotDomainCoverage, at date: Date
    ) async throws -> SnapshotID {
        try await base.writeSnapshot(
            grants: grants, launchAgents: launchAgents, btmItems: btmItems, coverage: coverage, at: date
        )
    }

    func pruneSnapshots(olderThan cutoff: Date, keeping protected: Set<SnapshotID>) async throws -> Int {
        try await base.pruneSnapshots(olderThan: cutoff, keeping: protected)
    }

    func diffTCCGrants(
        from: SnapshotID, to: SnapshotID, limitedTo services: Set<PermissionService>?
    ) async throws -> TCCGrantsDiff {
        try await base.diffTCCGrants(from: from, to: to, limitedTo: services)
    }

    func diffBTMItems(from: SnapshotID, to: SnapshotID) async throws -> BTMItemsDiff {
        try await base.diffBTMItems(from: from, to: to)
    }

    func diffLaunchAgents(from: SnapshotID, to: SnapshotID) async throws -> LaunchAgentsDiff {
        try await base.diffLaunchAgents(from: from, to: to)
    }
}
