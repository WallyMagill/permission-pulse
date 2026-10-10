import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct EvidenceChangedTests {
    private let grants = [StoreFixtures.grant("com.a")]
    private let agents = [StoreFixtures.agent("com.agent")]
    private let items = [StoreFixtures.btm("x")]

    private func storeWithBaseline(
        coverage: SnapshotDomainCoverage = .allComplete
    ) async throws -> (SnapshotStore, SnapshotID) {
        let store = try SnapshotStore.inMemory()
        let id = try await store.writeSnapshot(
            grants: grants, launchAgents: agents, btmItems: items,
            coverage: coverage, at: StoreFixtures.date
        )
        return (store, id)
    }

    @Test func identicalEvidenceIsUnchanged() async throws {
        let (store, id) = try await storeWithBaseline()
        let changed = try await store.evidenceChanged(
            since: id, grants: grants, launchAgents: agents, btmItems: items, coverage: .allComplete
        )
        #expect(!changed)
    }

    @Test func addedGrantIsAChange() async throws {
        let (store, id) = try await storeWithBaseline()
        let changed = try await store.evidenceChanged(
            since: id, grants: grants + [StoreFixtures.grant("com.b")],
            launchAgents: agents, btmItems: items, coverage: .allComplete
        )
        #expect(changed)
    }

    @Test func coverageFlipAloneIsAChange() async throws {
        let (store, id) = try await storeWithBaseline()
        let degraded = SnapshotDomainCoverage(tcc: .complete, btm: .complete, launchAgents: .degraded)
        let changed = try await store.evidenceChanged(
            since: id, grants: grants, launchAgents: agents, btmItems: items, coverage: degraded
        )
        #expect(changed)
    }

    @Test func itemsInAFailedDomainAreIgnored() async throws {
        let failedBTM = SnapshotDomainCoverage(tcc: .complete, btm: .failed, launchAgents: .complete)
        let (store, id) = try await storeWithBaseline(coverage: failedBTM)
        let changed = try await store.evidenceChanged(
            since: id, grants: grants, launchAgents: agents,
            btmItems: [StoreFixtures.btm("y")], coverage: failedBTM
        )
        #expect(!changed)
    }
}
