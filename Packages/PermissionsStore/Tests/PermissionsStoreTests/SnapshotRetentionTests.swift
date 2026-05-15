import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct SnapshotRetentionTests {
    @Test func pruneSnapshotsRemovesOldRowsAndCascades() async throws {
        let store = try SnapshotStore.inMemory()
        let day: TimeInterval = 24 * 60 * 60
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Write a full snapshot at -100d with one row in each child table.
        let oldDate = now.addingTimeInterval(-100 * day)
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

        let oldID = try await store.writeLaunchAgentsSnapshot([], at: now.addingTimeInterval(-100 * day))
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

