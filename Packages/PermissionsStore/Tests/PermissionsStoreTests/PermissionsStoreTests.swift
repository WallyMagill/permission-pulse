import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct PermissionsStoreSmokeTests {
    @Test func inMemoryStoreOpensAndMigratesToLatestSchema() throws {
        let store = try SnapshotStore.inMemory()
        let version = try store.schemaVersion()
        #expect(version == 4)
    }

    @Test func inMemoryStoreIsIdempotentOnReopen() throws {
        // Each in-memory store is independent; re-opening returns a fresh schema.
        let a = try SnapshotStore.inMemory()
        let b = try SnapshotStore.inMemory()
        #expect(try a.schemaVersion() == 4)
        #expect(try b.schemaVersion() == 4)
    }

    @Test func authValueRoundTripsAndSchemaIsV4() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 4)
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
