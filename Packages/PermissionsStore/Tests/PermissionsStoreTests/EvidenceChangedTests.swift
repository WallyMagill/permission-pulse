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

    // Stored dates keep millisecond precision; a fresh scan's sub-millisecond
    // BTM/TCC dates must not read as a change on every scan.
    @Test func subMillisecondDatesAreUnchanged() async throws {
        let precise = Date(timeIntervalSinceReferenceDate: 778_000_000.123_456_7)
        let grant = PermissionGrant(
            service: .camera,
            app: AppIdentity(bundleID: "com.a", displayName: "A", bundlePath: nil),
            lastModified: precise
        )
        let item = BTMItem(
            identifier: "x", name: "X", type: .app, disposition: .enabled,
            scope: .system, modificationDate: precise
        )
        let store = try SnapshotStore.inMemory()
        let id = try await store.writeFullSnapshot(grants: [grant], launchAgents: [], btmItems: [item])

        let changed = try await store.evidenceChanged(
            since: id, grants: [grant], launchAgents: [], btmItems: [item], coverage: .allComplete
        )
        #expect(!changed)
    }

    @Test func metadataOnlyChurnIsNotAChange() async throws {
        let (store, id) = try await storeWithBaseline()
        let grant = PermissionGrant(
            service: .camera,
            app: AppIdentity(bundleID: "com.a", displayName: "A 2.0",
                             bundlePath: URL(fileURLWithPath: "/Applications/A.app")),
            lastModified: StoreFixtures.date.addingTimeInterval(86_400)
        )
        let item = BTMItem(
            identifier: "x", name: "X renamed", bundleIdentifier: "com.example.x",
            type: .app, disposition: .enabled, dispositionRaw: 0x8b, scope: .system,
            modificationDate: StoreFixtures.date.addingTimeInterval(86_400)
        )
        let changed = try await store.evidenceChanged(
            since: id, grants: [grant], launchAgents: agents, btmItems: [item], coverage: .allComplete
        )
        #expect(!changed)
    }

    @Test func backgroundItemDisabledIsAChange() async throws {
        let (store, id) = try await storeWithBaseline()
        let disabled = BTMItem(
            identifier: "x", name: "Item-x", bundleIdentifier: "com.example.x",
            type: .app, disposition: .disabled, scope: .system, modificationDate: StoreFixtures.date
        )
        let changed = try await store.evidenceChanged(
            since: id, grants: grants, launchAgents: agents, btmItems: [disabled], coverage: .allComplete
        )
        #expect(changed)
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
