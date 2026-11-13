import Foundation
import GRDB
import Testing
import PermissionsCore
@testable import PermissionsStore

/// An upgrade compares a snapshot written under the old capture rules with
/// one written under the new ones. Facts only the new rules capture must not
/// read as fresh changes; between two current snapshots they are changes.
@Suite struct CaptureGenerationTests {
    private static let oldGrants = [StoreFixtures.grant("com.example.app")]
    private static let newGrants = oldGrants + [
        StoreFixtures.grant("com.p5sys.jump.connect", service: .remoteDesktop),
        StoreFixtures.grant("com.nordvpn.macos.Shield", service: .endpointSecurity),
    ]
    // The old decoder stored `[]` for a mixed-type array and ignored
    // launchd's override database.
    private static let oldAgents = [agent("com.logitech.LogiRightSight.Agent", arguments: [], disabled: false)]
    private static let newAgents = [agent("com.logitech.LogiRightSight.Agent", arguments: ["/bin/agent", "--quiet"], disabled: true)]

    @Test func migratedSnapshotsAreGenerationOneAndNewOnesCurrent() async throws {
        let url = StoreFixtures.temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try SnapshotV6Fixture.make(at: url.path)
        let store = try SnapshotStore(path: url.path)

        let written = try await store.writeFullSnapshot(grants: [], launchAgents: [], btmItems: [])

        #expect(try await store.captureGeneration(snapshotID: SnapshotV6Fixture.capturedSnapshotID) == 1)
        #expect(try await store.captureGeneration(snapshotID: written) == CaptureGeneration.current)
        #expect(CaptureGeneration.current == 2)
    }

    @Test func crossGenerationDiffIgnoresWhatTheOldRulesDidNotCapture() async throws {
        let store = try SnapshotStore.inMemory()
        let baseline = try await Self.write(store, grants: Self.oldGrants, agents: Self.oldAgents, generation: 1)
        let latest = try await Self.write(store, grants: Self.newGrants, agents: Self.newAgents)

        let tcc = try await store.diffTCCGrants(from: baseline, to: latest)
        let agents = try await store.diffLaunchAgents(from: baseline, to: latest)

        #expect(!tcc.hasContent)
        #expect(!agents.hasContent)
    }

    @Test func sameGenerationDiffReportsTheSameFacts() async throws {
        let store = try SnapshotStore.inMemory()
        let baseline = try await Self.write(store, grants: Self.oldGrants, agents: Self.oldAgents)
        let latest = try await Self.write(store, grants: Self.newGrants, agents: Self.newAgents)

        let tcc = try await store.diffTCCGrants(from: baseline, to: latest)
        let agents = try await store.diffLaunchAgents(from: baseline, to: latest)

        #expect(Set(tcc.added.map(\.service)) == [.remoteDesktop, .endpointSecurity])
        #expect(agents.changed == [DomainChange(before: Self.oldAgents[0], after: Self.newAgents[0])])
    }

    // A real change across generations still shows, without describing the
    // uncaptured fields as part of it.
    @Test func crossGenerationChangeRowCarriesTheUncapturedFields() async throws {
        let store = try SnapshotStore.inMemory()
        let moved = Self.agent(
            Self.newAgents[0].label, arguments: Self.newAgents[0].programArguments,
            disabled: true, path: "/opt/moved/agent"
        )
        let baseline = try await Self.write(store, grants: [], agents: Self.oldAgents, generation: 1)
        let latest = try await Self.write(store, grants: [StoreFixtures.grant("com.example.new")], agents: [moved])

        let tcc = try await store.diffTCCGrants(from: baseline, to: latest)
        let change = try #require(try await store.diffLaunchAgents(from: baseline, to: latest).changed.first)

        #expect(tcc.added.map(\.app.bundleID) == ["com.example.new"])
        #expect(change.before.programPath == Self.oldAgents[0].programPath)
        #expect(change.before.programArguments == moved.programArguments)
        #expect(change.before.isDisabled == moved.isDisabled)
    }

    // The first scan after upgrading must write a current-generation
    // snapshot that later scans compare against normally.
    @Test func olderGenerationBaselineAlwaysReadsAsChanged() async throws {
        let store = try SnapshotStore.inMemory()
        let old = try await Self.write(store, grants: Self.newGrants, agents: Self.newAgents, generation: 1)
        let current = try await Self.write(store, grants: Self.newGrants, agents: Self.newAgents)

        #expect(try await Self.evidenceChanged(store, since: old))
        #expect(try await !Self.evidenceChanged(store, since: current))
    }

    // MARK: - Helpers

    static func write(
        _ store: SnapshotStore,
        grants: [PermissionGrant],
        agents: [LaunchAgentItem],
        generation: Int = CaptureGeneration.current
    ) async throws -> SnapshotID {
        let id = try await store.writeFullSnapshot(grants: grants, launchAgents: agents, btmItems: [])
        try await store.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snapshots SET capture_generation = ? WHERE id = ?",
                arguments: [generation, id.rawValue]
            )
        }
        return id
    }

    private static func evidenceChanged(_ store: SnapshotStore, since id: SnapshotID) async throws -> Bool {
        try await store.evidenceChanged(
            since: id, grants: newGrants, launchAgents: newAgents, btmItems: [], coverage: .allComplete
        )
    }

    private static func agent(
        _ label: String,
        arguments: [String],
        disabled: Bool,
        path: String = "/Applications/Logi.app/agent"
    ) -> LaunchAgentItem {
        LaunchAgentItem(
            label: label,
            sourceDirectory: .userLaunchAgents,
            programPath: path,
            programArguments: arguments,
            runAtLoad: true,
            keepAlive: false,
            isDisabled: disabled
        )
    }
}
