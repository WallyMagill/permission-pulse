import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotBaselineTests {
    private let day: TimeInterval = 86_400

    private func summary(
        _ id: Int64,
        daysAgo: Double,
        tcc: SnapshotCoverage = .complete,
        btm: SnapshotCoverage = .complete
    ) -> SnapshotSummary {
        SnapshotSummary(
            id: SnapshotID(rawValue: id),
            date: StoreFixtures.date.addingTimeInterval(-daysAgo * day),
            coverage: SnapshotDomainCoverage(tcc: tcc, btm: btm, launchAgents: .complete)
        )
    }

    // A launch without Full Disk Access writes a snapshot with Permissions
    // failed; it must not hide the complete one before it.
    @Test func failedSnapshotAtTheCutoffFallsBackToTheLastCapture() {
        let older = summary(1, daysAgo: 3)
        let failed = summary(2, daysAgo: 1, tcc: .failed)

        let choice = BaselineSelector.choose(latest: .complete, candidates: [failed, older], domain: \.tcc)

        #expect(choice == .compared(older, systemLevelOnly: false))
        #expect(BaselineSelector.choose(latest: .complete, candidates: [failed, older], domain: \.btm)
            == .compared(failed, systemLevelOnly: false))
    }

    @Test func uncomparedDomainsCarryTheirCause() {
        let reduced = summary(1, daysAgo: 2, tcc: .reduced)
        let failed = summary(2, daysAgo: 1, tcc: .failed)
        let degraded = summary(3, daysAgo: 1, tcc: .degraded)

        #expect(BaselineSelector.choose(latest: .failed, candidates: [reduced], domain: \.tcc)
            == .notCompared(.latestScanFailed))
        #expect(BaselineSelector.choose(latest: .degraded, candidates: [reduced], domain: \.tcc)
            == .notCompared(.itemsUnreadable))
        #expect(BaselineSelector.choose(latest: .complete, candidates: [reduced], domain: \.tcc)
            == .notCompared(.scopeChanged))
        #expect(BaselineSelector.choose(latest: .complete, candidates: [failed], domain: \.tcc)
            == .notCompared(.noEarlierSnapshot))
        #expect(BaselineSelector.choose(latest: .complete, candidates: [degraded], domain: \.tcc)
            == .notCompared(.itemsUnreadable))
    }

    @Test func completeBaselineForReducedLatestComparesSystemLevelOnly() {
        let complete = summary(1, daysAgo: 2)

        #expect(BaselineSelector.choose(latest: .reduced, candidates: [complete], domain: \.tcc)
            == .compared(complete, systemLevelOnly: true))
    }

    @Test func pruneKeepsEachDomainsBaseline() async throws {
        let store = try SnapshotStore.inMemory()
        let now = StoreFixtures.date
        let superseded = try await write(store, daysAgo: 130)
        let lastCapture = try await write(store, daysAgo: 120)
        _ = try await write(
            store, daysAgo: 100,
            coverage: SnapshotDomainCoverage(tcc: .failed, btm: .failed, launchAgents: .complete)
        )
        _ = try await write(store, daysAgo: 0)

        let removed = try await store.pruneSnapshots(olderThan: now.addingTimeInterval(-90 * day))

        #expect(removed == 1)
        #expect(try await store.snapshotSummary(id: lastCapture) != nil)
        #expect(try await store.snapshotSummary(id: superseded) == nil)
    }

    @Test func pruneKeepsProtectedSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let reviewed = try await write(store, daysAgo: 130)
        let superseded = try await write(store, daysAgo: 120)
        _ = try await write(store, daysAgo: 100)
        _ = try await write(store, daysAgo: 0)

        _ = try await store.pruneSnapshots(
            olderThan: StoreFixtures.date.addingTimeInterval(-90 * day),
            keeping: [reviewed]
        )

        #expect(try await store.snapshotSummary(id: reviewed) != nil)
        #expect(try await store.snapshotSummary(id: superseded) == nil)
    }

    private func write(
        _ store: SnapshotStore,
        daysAgo: Double,
        coverage: SnapshotDomainCoverage = .allComplete
    ) async throws -> SnapshotID {
        try await store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [], coverage: coverage,
            at: StoreFixtures.date.addingTimeInterval(-daysAgo * day)
        )
    }

    @Test func narrowedDiffIgnoresServicesTheLaterScanCannotSee() async throws {
        let store = try SnapshotStore.inMemory()
        let before = try await store.writeFullSnapshot(
            grants: [
                StoreFixtures.grant("com.example.kept", service: .accessibility),
                StoreFixtures.grant("com.example.hidden", service: .microphone),
            ],
            launchAgents: [], btmItems: [], at: StoreFixtures.date
        )
        let after = try await store.writeSnapshot(
            grants: [StoreFixtures.grant("com.example.new", service: .screenRecording)],
            launchAgents: [], btmItems: [],
            coverage: SnapshotDomainCoverage(tcc: .reduced, btm: .complete, launchAgents: .complete),
            at: StoreFixtures.date.addingTimeInterval(day)
        )

        let diff = try await store.diffTCCGrants(from: before, to: after, limitedTo: PermissionService.systemLevel)

        #expect(diff.added.map(\.app.bundleID) == ["com.example.new"])
        #expect(diff.removed.map(\.app.bundleID) == ["com.example.kept"])
    }
}
