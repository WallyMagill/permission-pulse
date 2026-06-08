import Foundation
import Testing
@testable import PermissionsStore

@Suite struct BTMDecodeErrorTests {
    @Test func unknownTypeKindThrows() {
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeItemType(kind: "bogus-type", raw: nil)
        }
    }

    @Test func unknownDispositionKindThrows() {
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeDisposition(kind: "bogus-disposition", raw: nil)
        }
    }

    @Test func unknownScopeKindThrows() {
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeScope(kind: "bogus-scope", uuid: nil)
        }
    }

    @Test func perUserScopeWithMissingUUIDThrows() {
        // A "perUser" scope row with a NULL uuid is a corruption state; it must
        // throw (StoreError.missingPerUserScopeUUID), not silently produce a
        // bogus scope. (R3)
        #expect(throws: StoreError.self) {
            _ = try SnapshotStore.decodeScope(kind: "perUser", uuid: nil)
        }
    }

    @Test func knownKindsStillDecode() throws {
        #expect(try SnapshotStore.decodeItemType(kind: "app", raw: nil) == .app)
        #expect(try SnapshotStore.decodeDisposition(kind: "enabled", raw: nil) == .enabled)
        #expect(try SnapshotStore.decodeScope(kind: "system", uuid: nil) == .system)
    }
}
