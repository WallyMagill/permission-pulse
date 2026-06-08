import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotDateEncodingTests {
    @Test func datesRoundTripToMillisecond() async throws {
        let store = try SnapshotStore.inMemory()
        let when = Date(timeIntervalSince1970: 1_700_000_000.123)
        let grant = PermissionGrant(
            service: .filesAndFolders,
            app: AppIdentity(bundleID: "com.example.app", displayName: "App"),
            lastModified: when
        )
        let sid = try await store.writeTCCGrantsSnapshot([grant], at: when)
        let read = try await store.readTCCGrants(snapshotID: sid)
        // GRDB TEXT date encoding is millisecond-precision; assert within ~1ms.
        let delta = abs((read.first?.lastModified.timeIntervalSince1970 ?? 0) - when.timeIntervalSince1970)
        #expect(delta < 0.0011)
    }

    @Test func latestSnapshotOrderingIsChronologicalNotInsertionOrder() async throws {
        let store = try SnapshotStore.inMemory()
        // Insert OUT of chronological order: first insert has the NEWEST date.
        let newestID = try await store.writeTCCGrantsSnapshot([], at: Date(timeIntervalSince1970: 3_000_000_000))
        let middleID = try await store.writeTCCGrantsSnapshot([], at: Date(timeIntervalSince1970: 1_000_000_000))
        // The newest DATE must win even though it was inserted first (id is lower).
        let latest = try await store.latestSnapshotID()
        #expect(latest == newestID)
        #expect(latest != middleID)
        // atOrBefore a cutoff between the two dates returns the older one.
        let atOrBeforeOld = try await store.latestSnapshotID(atOrBefore: Date(timeIntervalSince1970: 1_500_000_000))
        #expect(atOrBeforeOld == middleID)
    }
}
