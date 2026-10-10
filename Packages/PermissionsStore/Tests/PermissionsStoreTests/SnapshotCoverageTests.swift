import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotCoverageTests {
    @Test func legacySnapshotsMigrateAsComplete() async throws {
        let url = StoreFixtures.temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try SnapshotV4Fixture.make(at: url.path)

        let store = try SnapshotStore(path: url.path)

        #expect(try store.schemaVersion() == 6)
        #expect(try await store.coverage(snapshotID: SnapshotV4Fixture.legacySnapshotID) == .allComplete)
    }

    @Test func coverageRoundTrips() async throws {
        let store = try SnapshotStore.inMemory()
        let coverage = SnapshotDomainCoverage(tcc: .complete, btm: .failed, launchAgents: .degraded)

        let id = try await store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [], coverage: coverage, at: StoreFixtures.date
        )

        #expect(try await store.coverage(snapshotID: id) == coverage)
        #expect(try await store.snapshotDate(snapshotID: id) == StoreFixtures.date)
    }

    @Test func failedDomainStoresNoRows() async throws {
        let store = try SnapshotStore.inMemory()

        let id = try await store.writeSnapshot(
            grants: [StoreFixtures.grant("com.a")],
            launchAgents: [StoreFixtures.agent("com.agent")],
            btmItems: [StoreFixtures.btm("x")],
            coverage: SnapshotDomainCoverage(tcc: .failed, btm: .complete, launchAgents: .failed),
            at: StoreFixtures.date
        )

        #expect(try await store.readTCCGrants(snapshotID: id).isEmpty)
        #expect(try await store.readLaunchAgents(snapshotID: id).isEmpty)
        #expect(try await store.readBTMItems(snapshotID: id).count == 1)
    }
}
