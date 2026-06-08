import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct TCCDiffTests {
    @Test func migrationV3CreatesTCCGrantsTable() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 3)
        let id = try await store.writeTCCGrantsSnapshot([])
        let grants = try await store.readTCCGrants(snapshotID: id)
        #expect(grants.isEmpty)
    }

    @Test func writeAndReadRoundTripsGrants() async throws {
        let store = try SnapshotStore.inMemory()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let grants = [
            grant(service: .screenRecording, bundleID: "com.example.alpha"),
            grant(
                service: .automation,
                bundleID: "com.example.beta",
                automationTarget: "com.apple.finder",
                bundlePath: URL(fileURLWithPath: "/Applications/Beta.app")
            ),
        ]
        let id = try await store.writeTCCGrantsSnapshot(grants, at: date)
        let read = try await store.readTCCGrants(snapshotID: id)
        #expect(read.count == 2)
        #expect(Set(read) == Set(grants))
    }

    @Test func diffReturnsAddedAndRemovedBetweenSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let a = grant(service: .microphone, bundleID: "com.example.a")
        let b = grant(service: .camera, bundleID: "com.example.b")
        let c = grant(service: .screenRecording, bundleID: "com.example.c")

        let firstID = try await store.writeTCCGrantsSnapshot([a, b])
        let secondID = try await store.writeTCCGrantsSnapshot([a, c])
        let diff = try await store.diffTCCGrants(from: firstID, to: secondID)

        #expect(diff.added == [c])
        #expect(diff.removed == [b])
        #expect(diff.changed.isEmpty)
    }

    @Test func diffReturnsEmptyForIdenticalSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let grants = [
            grant(service: .microphone, bundleID: "com.example.x"),
            grant(service: .camera, bundleID: "com.example.y"),
        ]
        let firstID = try await store.writeTCCGrantsSnapshot(grants)
        let secondID = try await store.writeTCCGrantsSnapshot(grants)
        let diff = try await store.diffTCCGrants(from: firstID, to: secondID)

        #expect(!diff.hasContent)
    }

    @Test func automationTargetIsPartOfIdentity() async throws {
        let store = try SnapshotStore.inMemory()
        let toFinder = grant(
            service: .automation,
            bundleID: "com.example.terminal",
            automationTarget: "com.apple.finder"
        )
        let toSystemEvents = grant(
            service: .automation,
            bundleID: "com.example.terminal",
            automationTarget: "com.apple.systemevents"
        )

        let firstID = try await store.writeTCCGrantsSnapshot([toFinder, toSystemEvents])
        let secondID = try await store.writeTCCGrantsSnapshot([toSystemEvents])
        let diff = try await store.diffTCCGrants(from: firstID, to: secondID)

        #expect(diff.removed == [toFinder])
        #expect(diff.added.isEmpty)
    }

    @Test func diffDoesNotTrapOnDuplicateIdentityKeys() async throws {
        // Two grants that genuinely share the same identity (same service,
        // same bundleID, same automationTarget) must not trap the diff engine.
        // D1 unified the identity key so path-only grants now use the path
        // instead of bundleID — but identical-identity bundle-ID grants can
        // still occur (e.g. user + system TCC dbs both containing the same
        // row). The diff engine must survive that via uniquingKeysWith.
        let store = try SnapshotStore.inMemory()
        let dup = grant(service: .filesAndFolders, bundleID: "com.example.shared")
        // Write the same grant twice to simulate a genuine key collision at
        // the store layer (scanner dedupe already filters these, but the store
        // must not trap even if fed duplicates).
        let other = grant(service: .microphone, bundleID: "com.example.mic")

        let firstID = try await store.writeTCCGrantsSnapshot([])
        let secondID = try await store.writeTCCGrantsSnapshot([dup, dup, other])

        let diff = try await store.diffTCCGrants(from: firstID, to: secondID)
        #expect(diff.added.count == 2, "two distinct identity keys: filesAndFolders|com.example.shared| and microphone|com.example.mic|")
        #expect(diff.removed.isEmpty)
    }

    @Test func distinctPathOnlyGrantsBothAppearInDiff() async throws {
        let store = try SnapshotStore.inMemory()
        let s1 = try await store.writeTCCGrantsSnapshot([], at: Date(timeIntervalSince1970: 0))
        let toolA = PermissionGrant(
            service: .filesAndFolders,
            app: AppIdentity(
                bundleID: "",
                displayName: "tool-a",
                bundlePath: URL(fileURLWithPath: "/usr/local/bin/tool-a")
            ),
            lastModified: Date(timeIntervalSince1970: 100)
        )
        let toolB = PermissionGrant(
            service: .filesAndFolders,
            app: AppIdentity(
                bundleID: "",
                displayName: "tool-b",
                bundlePath: URL(fileURLWithPath: "/usr/local/bin/tool-b")
            ),
            lastModified: Date(timeIntervalSince1970: 100)
        )
        let s2 = try await store.writeTCCGrantsSnapshot([toolA, toolB], at: Date(timeIntervalSince1970: 200))
        let diff = try await store.diffTCCGrants(from: s1, to: s2)
        #expect(diff.added.count == 2)
        #expect(Set(diff.added) == Set([toolA, toolB]))
    }

    private func grant(
        service: PermissionService,
        bundleID: String,
        automationTarget: String? = nil,
        bundlePath: URL? = nil
    ) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(
                bundleID: bundleID,
                displayName: bundleID.split(separator: ".").last.map(String.init) ?? bundleID,
                bundlePath: bundlePath
            ),
            lastModified: Date(timeIntervalSince1970: 1_700_000_000),
            automationTarget: automationTarget
        )
    }
}
