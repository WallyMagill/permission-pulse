import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotDiscoveryTests {
    @Test func latestSnapshotIDAtOrBeforeReturnsNilWhenNone() async throws {
        let store = try SnapshotStore.inMemory()
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let id = try await store.latestSnapshotID(atOrBefore: cutoff)
        #expect(id == nil)

        let latest = try await store.latestSnapshotID()
        #expect(latest == nil)
    }

    @Test func latestSnapshotIDAtOrBeforeReturnsClosestPriorSnapshot() async throws {
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let tenDaysAgo = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-10 * day))
        let threeDaysAgo = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-3 * day))
        let oneDayAgo = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-1 * day))
        let today = try await store.writeLaunchAgentsSnapshot([], at: now)

        // cutoff = -2d → expect the -3d snapshot
        let twoDaysAgo = now.addingTimeInterval(-2 * day)
        let found = try await store.latestSnapshotID(atOrBefore: twoDaysAgo)
        #expect(found == threeDaysAgo)

        // cutoff = -5d → still -10d (no -3d-or-earlier ≤ -5d snapshot exists)
        let fiveDaysAgo = now.addingTimeInterval(-5 * day)
        let earlier = try await store.latestSnapshotID(atOrBefore: fiveDaysAgo)
        #expect(earlier == tenDaysAgo)

        // latestSnapshotID() returns the freshest absolutely
        let latest = try await store.latestSnapshotID()
        #expect(latest == today)

        _ = oneDayAgo // silence unused-var warning
    }

    @Test func latestSnapshotIDIsByDateNotByInsertionOrder() async throws {
        // Out-of-order inserts (test seeding, manual sqlite, restored
        // backups) should still resolve to the actually-newest date. This
        // guards against a regression where the query orders by id.
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let today = try await store.writeLaunchAgentsSnapshot([], at: now)
        let twoDaysAgo = try await store.writeLaunchAgentsSnapshot(
            [], at: now.addingTimeInterval(-2 * day)
        )
        // Second insert has the higher id but the older date. The freshest
        // by created_at is `today`, NOT `twoDaysAgo`.
        #expect(today.rawValue < twoDaysAgo.rawValue)
        let latest = try await store.latestSnapshotID()
        #expect(latest == today)
    }
}
