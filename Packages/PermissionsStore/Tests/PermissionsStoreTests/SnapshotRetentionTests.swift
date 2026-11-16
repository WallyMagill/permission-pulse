import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotRetentionTests {
    @Test func pruneSnapshotsRemovesOldRowsAndCascades() async throws {
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Write a full snapshot at -120d with one row in each child table.
        let oldDate = now.addingTimeInterval(-120 * day)
        _ = try await store.writeFullSnapshot(
            grants: [
                PermissionGrant(
                    service: .microphone,
                    app: AppIdentity(bundleID: "com.example.a", displayName: "A"),
                    lastModified: oldDate
                ),
            ],
            launchAgents: [
                LaunchAgentItem(
                    label: "com.example.a",
                    sourceDirectory: .userLaunchAgents,
                    programPath: "/bin/a",
                    programArguments: [],
                    runAtLoad: true,
                    keepAlive: false
                ),
            ],
            btmItems: [
                BTMItem(
                    identifier: "com.example.a",
                    name: "A",
                    type: .app,
                    disposition: .enabled,
                    scope: .system,
                    modificationDate: oldDate
                ),
            ],
            at: oldDate
        )

        // Confirm child rows exist via low-level SQL count.
        try await assertChildRowCounts(in: store, expected: (tcc: 1, btm: 1, la: 1))

        // A newer (still pre-cutoff) empty snapshot becomes the retained baseline.
        _ = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-100 * day))

        // Prune anything older than 90 days.
        let cutoff = now.addingTimeInterval(-90 * day)
        let removed = try await store.pruneSnapshots(olderThan: cutoff)
        #expect(removed == 1)

        // Child rows should be gone via FK CASCADE.
        try await assertChildRowCounts(in: store, expected: (tcc: 0, btm: 0, la: 0))
    }

    @Test func pruneSnapshotsKeepsRowsAtOrAfterCutoff() async throws {
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let oldID = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-110 * day))
        _ = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-100 * day))
        let recentID = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-1 * day))

        let removed = try await store.pruneSnapshots(olderThan: now.addingTimeInterval(-90 * day))
        #expect(removed == 1)

        // Recent snapshot still readable; old one gone.
        let recent = try await store.readLaunchAgents(snapshotID: recentID)
        #expect(recent.isEmpty)

        let latest = try await store.latestSnapshotID()
        #expect(latest == recentID)

        _ = oldID
    }

    // With change-only writes the newest pre-cutoff snapshot is the state at
    // the cutoff, so deleting it would erase the comparison baseline.
    @Test func pruneKeepsTheOnlySnapshotEvenWhenOld() async throws {
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let onlyID = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-100 * day))

        let removed = try await store.pruneSnapshots(olderThan: now.addingTimeInterval(-90 * day))

        #expect(removed == 0)
        #expect(try await store.latestSnapshotID() == onlyID)
    }

    @Test func pruneKeepsBaselineAndLatestOnly() async throws {
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for offset in [-130.0, -120, -110] {
            _ = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(offset * day))
        }
        let baselineID = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-100 * day))
        let latestID = try await store.writeLaunchAgentsSnapshot([], at: now)

        let removed = try await store.pruneSnapshots(olderThan: now.addingTimeInterval(-90 * day))

        #expect(removed == 3)
        #expect(try await store.latestSnapshotID(atOrBefore: now.addingTimeInterval(-90 * day)) == baselineID)
        #expect(try await store.latestSnapshotID() == latestID)
    }

    private func assertChildRowCounts(
        in store: SnapshotStore,
        expected: (tcc: Int, btm: Int, la: Int)
    ) async throws {
        let counts = try await store.unsafeChildRowCounts()
        #expect(counts.tcc == expected.tcc)
        #expect(counts.btm == expected.btm)
        #expect(counts.la == expected.la)
    }
}

