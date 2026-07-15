import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct PermissionsStoreSmokeTests {
    @Test func inMemoryStoreOpensAndMigratesToLatestSchema() throws {
        let store = try SnapshotStore.inMemory()
        let version = try store.schemaVersion()
        #expect(version == 5)
    }

    @Test func inMemoryStoreIsIdempotentOnReopen() throws {
        // Each in-memory store is independent; re-opening returns a fresh schema.
        let a = try SnapshotStore.inMemory()
        let b = try SnapshotStore.inMemory()
        #expect(try a.schemaVersion() == 5)
        #expect(try b.schemaVersion() == 5)
    }

    @Test func authValueRoundTripsAndSchemaIsV5() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 5)
        let limited = PermissionGrant(
            service: .photos,
            app: AppIdentity(bundleID: "com.example.photoapp", displayName: "PhotoApp"),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 3
        )
        let sid = try await store.writeTCCGrantsSnapshot([limited], at: Date(timeIntervalSince1970: 1))
        let read = try await store.readTCCGrants(snapshotID: sid)
        #expect(read.count == 1)
        #expect(read.first?.authValue == 3)
    }
}
