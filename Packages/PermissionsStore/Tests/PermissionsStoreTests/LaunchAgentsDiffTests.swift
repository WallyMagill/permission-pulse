import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct LaunchAgentsDiffTests {
    @Test func migrationCreatesLaunchAgentsTable() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 5)
        // If the table is missing, an empty read still throws on schema. Issue a
        // benign write/read round-trip instead — proves the table is queryable.
        let id = try await store.writeLaunchAgentsSnapshot([])
        let items = try await store.readLaunchAgents(snapshotID: id)
        #expect(items.isEmpty)
    }

    @Test func writeAndReadRoundTripsItems() async throws {
        let store = try SnapshotStore.inMemory()
        let items = [
            LaunchAgentItem(
                label: "com.example.alpha",
                sourceDirectory: .userLaunchAgents,
                programPath: "/usr/local/bin/alpha",
                programArguments: ["--flag", "value"],
                runAtLoad: true,
                keepAlive: false,
                isDisabled: true
            ),
            LaunchAgentItem(
                label: "com.example.beta",
                sourceDirectory: .libraryLaunchDaemons,
                programPath: nil,
                programArguments: [],
                runAtLoad: false,
                keepAlive: true
            ),
        ]

        let id = try await store.writeLaunchAgentsSnapshot(items)
        let read = try await store.readLaunchAgents(snapshotID: id)

        #expect(read.count == 2)
        #expect(Set(read) == Set(items))
    }

    @Test func v4MigrationRetainsHistoryAndMarksLegacySnapshotUncaptured() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try SnapshotV4Fixture.make(at: databaseURL.path)

        let store = try SnapshotStore(path: databaseURL.path)

        #expect(try store.schemaVersion() == 5)
        #expect(try await store.latestSnapshotID() == SnapshotV4Fixture.legacySnapshotID)
        #expect(try await store.readLaunchAgents(snapshotID: SnapshotV4Fixture.legacySnapshotID) == [legacyItem()])
        #expect(try await store.readTCCGrants(snapshotID: SnapshotV4Fixture.legacySnapshotID).count == 1)
        #expect(try await store.readBTMItems(snapshotID: SnapshotV4Fixture.legacySnapshotID).count == 1)
        #expect(try SnapshotV4Fixture.launchAgentCaptureMarker(
            at: databaseURL.path,
            snapshotID: SnapshotV4Fixture.legacySnapshotID
        ) == false)
    }

    @Test func legacyToV5DisabledOnlyDifferenceDoesNotCreateTransition() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try SnapshotV4Fixture.make(at: databaseURL.path)
        let store = try SnapshotStore(path: databaseURL.path)

        let capturedDisabled = launchAgent(isDisabled: true)
        let newID = try await store.writeLaunchAgentsSnapshot([capturedDisabled])
        let diff = try await store.diffLaunchAgents(
            from: SnapshotV4Fixture.legacySnapshotID,
            to: newID
        )

        #expect(!diff.hasContent)
        #expect(try SnapshotV4Fixture.launchAgentCaptureMarker(
            at: databaseURL.path,
            snapshotID: newID
        ))
    }

    @Test func v5DisabledFalseToTrueCreatesExactlyOneTransition() async throws {
        let store = try SnapshotStore.inMemory()
        let before = launchAgent(isDisabled: false)
        let after = launchAgent(isDisabled: true)

        let beforeID = try await store.writeLaunchAgentsSnapshot([before])
        let afterID = try await store.writeLaunchAgentsSnapshot([after])
        let diff = try await store.diffLaunchAgents(from: beforeID, to: afterID)

        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.changed == [DomainChange(before: before, after: after)])
    }

    @Test func migratedDatabaseReopensWithoutReapplyingV5() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try SnapshotV4Fixture.make(at: databaseURL.path)

        let firstOpen = try SnapshotStore(path: databaseURL.path)
        #expect(try firstOpen.schemaVersion() == 5)
        let secondOpen = try SnapshotStore(path: databaseURL.path)

        #expect(try secondOpen.schemaVersion() == 5)
        #expect(try await secondOpen.readLaunchAgents(
            snapshotID: SnapshotV4Fixture.legacySnapshotID
        ) == [legacyItem()])
    }

    @Test func diffReturnsAddedAndRemovedBetweenSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let a = item("com.example.a")
        let b = item("com.example.b")
        let c = item("com.example.c")

        let firstID = try await store.writeLaunchAgentsSnapshot([a, b])
        let secondID = try await store.writeLaunchAgentsSnapshot([a, c])
        let diff = try await store.diffLaunchAgents(from: firstID, to: secondID)

        #expect(diff.added == [c])
        #expect(diff.removed == [b])
    }

    @Test func diffReturnsEmptyForIdenticalSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let items = [item("com.example.x"), item("com.example.y")]

        let firstID = try await store.writeLaunchAgentsSnapshot(items)
        let secondID = try await store.writeLaunchAgentsSnapshot(items)
        let diff = try await store.diffLaunchAgents(from: firstID, to: secondID)

        #expect(!diff.hasContent)
    }

    @Test func runAtLoadFlipAppearsInChangedArm() async throws {
        let store = try SnapshotStore.inMemory()
        let before = LaunchAgentItem(
            label: "com.example.foo",
            sourceDirectory: .userLaunchAgents,
            programPath: "/bin/foo",
            programArguments: [],
            runAtLoad: true,
            keepAlive: false
        )
        let after = LaunchAgentItem(
            label: "com.example.foo",
            sourceDirectory: .userLaunchAgents,
            programPath: "/bin/foo",
            programArguments: [],
            runAtLoad: false,
            keepAlive: false
        )
        let firstID = try await store.writeLaunchAgentsSnapshot([before])
        let secondID = try await store.writeLaunchAgentsSnapshot([after])
        let diff = try await store.diffLaunchAgents(from: firstID, to: secondID)

        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.changed == [DomainChange(before: before, after: after)])
    }

    private func item(_ label: String) -> LaunchAgentItem {
        LaunchAgentItem(
            label: label,
            sourceDirectory: .userLaunchAgents,
            programPath: "/usr/local/bin/\(label)",
            programArguments: [],
            runAtLoad: true,
            keepAlive: false
        )
    }

    private func launchAgent(isDisabled: Bool) -> LaunchAgentItem {
        LaunchAgentItem(
            label: "com.example.disabled",
            sourceDirectory: .userLaunchAgents,
            programPath: "/usr/local/bin/disabled",
            programArguments: ["--legacy"],
            runAtLoad: true,
            keepAlive: false,
            isDisabled: isDisabled
        )
    }

    private func legacyItem() -> LaunchAgentItem {
        launchAgent(isDisabled: false)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("permission-pulse-v4-\(UUID().uuidString).sqlite")
    }
}
