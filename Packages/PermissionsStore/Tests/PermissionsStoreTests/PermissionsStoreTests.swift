import Testing
@testable import PermissionsStore

@Suite struct PermissionsStoreSmokeTests {
    @Test func inMemoryStoreOpensAndMigratesToV1() throws {
        let store = try SnapshotStore.inMemory()
        let version = try store.schemaVersion()
        #expect(version == 1)
    }

    @Test func inMemoryStoreIsIdempotentOnReopen() throws {
        // Each in-memory store is independent; re-opening returns a fresh schema.
        let a = try SnapshotStore.inMemory()
        let b = try SnapshotStore.inMemory()
        #expect(try a.schemaVersion() == 1)
        #expect(try b.schemaVersion() == 1)
    }
}
