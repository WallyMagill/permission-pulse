import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct LaunchAgentsV7Tests {
    // A fresh scan of the same agents now also records the file name, reads
    // launchd's override database, and keeps the string elements of a mixed
    // ProgramArguments array. None of that may show as a change against the
    // migrated v6 snapshot on the first scan after upgrading.
    @Test func migratedV6SnapshotMatchesAFreshScanOfTheSameAgents() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("permission-pulse-v6-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try SnapshotV6Fixture.make(at: databaseURL.path)

        let store = try SnapshotStore(path: databaseURL.path)
        let freshScan = SnapshotV6Fixture.agents.map { agent in
            copy(agent, fileName: "\(agent.label).plist")
        }.map { agent in
            guard agent.label == "com.example.updater" else { return agent }
            return copy(agent, arguments: [agent.programPath ?? "", "--daemon"], disabled: true)
        }

        #expect(try store.schemaVersion() == 7)
        let migrated = try await store.readLaunchAgents(snapshotID: SnapshotV6Fixture.capturedSnapshotID)
        #expect(migrated.count == 2)
        #expect(migrated.allSatisfy { $0.detailsReadable && $0.fileName == nil })
        #expect(try await store.evidenceChanged(
            since: SnapshotV6Fixture.capturedSnapshotID,
            grants: [], launchAgents: freshScan, btmItems: [], coverage: .allComplete
        ))
        let written = try await store.writeFullSnapshot(grants: [], launchAgents: freshScan, btmItems: [])
        let diff = try await store.diffLaunchAgents(from: SnapshotV6Fixture.capturedSnapshotID, to: written)
        #expect(!diff.hasContent)
        #expect(try await !store.evidenceChanged(
            since: written, grants: [], launchAgents: freshScan, btmItems: [], coverage: .allComplete
        ))
    }

    @Test func unreadableItemRoundTripsReadabilityAndFileName() async throws {
        let store = try SnapshotStore.inMemory()
        let locked = LaunchAgentItem(
            label: "com.example.locked",
            sourceDirectory: .libraryLaunchDaemons,
            programPath: nil,
            programArguments: [],
            runAtLoad: false,
            keepAlive: false,
            detailsReadable: false,
            fileName: "com.example.locked.plist"
        )

        let id = try await store.writeLaunchAgentsSnapshot([locked])

        #expect(try await store.readLaunchAgents(snapshotID: id) == [locked])
    }

    @Test func readabilityFlipIsAChange() async throws {
        let store = try SnapshotStore.inMemory()
        let readable = StoreFixtures.agent("com.example.flip")
        let unreadable = LaunchAgentItem(
            label: readable.label,
            sourceDirectory: readable.sourceDirectory,
            programPath: nil,
            programArguments: [],
            runAtLoad: false,
            keepAlive: false,
            detailsReadable: false
        )

        let beforeID = try await store.writeLaunchAgentsSnapshot([readable])
        let afterID = try await store.writeLaunchAgentsSnapshot([unreadable])
        let diff = try await store.diffLaunchAgents(from: beforeID, to: afterID)

        #expect(diff.changed == [DomainChange(before: readable, after: unreadable)])
    }

    // A legacy endpoint stored `isDisabled = false` as a placeholder; a change
    // row for another field must not read it as an enabled → disabled flip.
    @Test func uncapturedDisabledIsNotReportedAsATransition() throws {
        let before = StoreFixtures.agent("com.example.legacy")
        let after = LaunchAgentItem(
            label: before.label,
            sourceDirectory: before.sourceDirectory,
            programPath: "/usr/local/bin/new",
            programArguments: before.programArguments,
            runAtLoad: before.runAtLoad,
            keepAlive: before.keepAlive,
            isDisabled: true
        )

        let diff = SnapshotStore.diffLaunchAgents(before: [before], after: [after], compareDisabled: false)

        let change = try #require(diff.changed.first)
        #expect(change.before.isDisabled == true)
        #expect(change.before.programPath == before.programPath)
    }

    private func copy(
        _ item: LaunchAgentItem,
        fileName: String? = nil,
        arguments: [String]? = nil,
        disabled: Bool? = nil
    ) -> LaunchAgentItem {
        LaunchAgentItem(
            label: item.label,
            sourceDirectory: item.sourceDirectory,
            programPath: item.programPath,
            programArguments: arguments ?? item.programArguments,
            runAtLoad: item.runAtLoad,
            keepAlive: item.keepAlive,
            isDisabled: disabled ?? item.isDisabled,
            detailsReadable: item.detailsReadable,
            fileName: fileName ?? item.fileName
        )
    }
}
