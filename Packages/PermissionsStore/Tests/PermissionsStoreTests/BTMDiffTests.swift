import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct BTMDiffTests {
    @Test func migrationV3CreatesBTMItemsTable() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 7)
        let id = try await store.writeBTMItemsSnapshot([])
        let items = try await store.readBTMItems(snapshotID: id)
        #expect(items.isEmpty)
    }

    @Test func writeAndReadRoundTripsItemsWithAllEnumCases() async throws {
        let store = try SnapshotStore.inMemory()
        // One item per ItemType, including unknown(raw:). One per Disposition.
        // One per Scope including perUser(uuid:).
        let items: [BTMItem] = [
            item(id: "a", type: .app, disposition: .enabled, scope: .system),
            item(id: "b", type: .legacyDaemon, disposition: .disabled, scope: .user),
            item(id: "c", type: .developerGroup, disposition: .enabled,
                 scope: .perUser(uuid: "EBE3FCE9-AAB7-4856-9DE0-DA73CD18AAEE")),
            item(id: "d", type: .unknown(rawValue: 99),
                 disposition: .unknown(rawValue: 7), scope: .system),
            item(id: "e", type: .loginItem), item(id: "f", type: .agent),
            item(id: "g", type: .spotlightImporter), item(id: "h", type: .dockTilePlugin),
            item(id: "i", type: .quickLookExtension), item(id: "j", type: .backgroundTasks),
            item(id: "k", type: .legacyAgent),
        ]
        let snapshotID = try await store.writeBTMItemsSnapshot(items)
        let read = try await store.readBTMItems(snapshotID: snapshotID)
        #expect(read.count == items.count)
        #expect(Set(read) == Set(items))
    }

    @Test func diffReturnsAddedAndRemovedBetweenSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let a = item(id: "a")
        let b = item(id: "b")
        let c = item(id: "c")

        let firstID = try await store.writeBTMItemsSnapshot([a, b])
        let secondID = try await store.writeBTMItemsSnapshot([a, c])
        let diff = try await store.diffBTMItems(from: firstID, to: secondID)

        #expect(diff.added == [c])
        #expect(diff.removed == [b])
        #expect(diff.changed.isEmpty)
    }

    @Test func diffReturnsEmptyForIdenticalSnapshots() async throws {
        let store = try SnapshotStore.inMemory()
        let items = [item(id: "x"), item(id: "y")]
        let firstID = try await store.writeBTMItemsSnapshot(items)
        let secondID = try await store.writeBTMItemsSnapshot(items)
        let diff = try await store.diffBTMItems(from: firstID, to: secondID)

        #expect(!diff.hasContent)
    }

    @Test func dispositionFlipAppearsInChangedArm() async throws {
        let store = try SnapshotStore.inMemory()
        let before = item(id: "shared", disposition: .enabled)
        let after = item(id: "shared", disposition: .disabled)

        let firstID = try await store.writeBTMItemsSnapshot([before])
        let secondID = try await store.writeBTMItemsSnapshot([after])
        let diff = try await store.diffBTMItems(from: firstID, to: secondID)

        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.changed == [DomainChange(before: before, after: after)])
    }

    @Test func perUserUUIDRoundTripsThroughScopeColumns() async throws {
        let store = try SnapshotStore.inMemory()
        let uuid = "EBE3FCE9-AAB7-4856-9DE0-DA73CD18AAEE"
        let original = item(id: "scoped", scope: .perUser(uuid: uuid))

        let snapshotID = try await store.writeBTMItemsSnapshot([original])
        let read = try await store.readBTMItems(snapshotID: snapshotID)

        #expect(read.count == 1)
        #expect(read[0].scope == .perUser(uuid: uuid))
    }

    @Test func dispositionRawRoundTripsAndDoesNotCreateDiffNoise() async throws {
        let store = try SnapshotStore.inMemory()
        func item(raw: Int) -> BTMItem {
            BTMItem(identifier: "com.example.helper", name: "Helper",
                    type: .legacyDaemon, disposition: .disabled, dispositionRaw: raw,
                    scope: .system, modificationDate: Date(timeIntervalSince1970: 0))
        }
        // Round-trip preserves the raw bits in the persisted snapshot.
        let s1 = try await store.writeBTMItemsSnapshot([item(raw: 5)], at: Date(timeIntervalSince1970: 1))
        let read = try await store.readBTMItems(snapshotID: s1)
        #expect(read.first?.dispositionRaw == 5)
        // Two items identical except dispositionRaw must NOT show as a change
        // (raw is excluded from Equatable; representing it is deferred).
        let s2 = try await store.writeBTMItemsSnapshot([item(raw: 9)], at: Date(timeIntervalSince1970: 2))
        let diff = try await store.diffBTMItems(from: s1, to: s2)
        #expect(diff.changed.isEmpty)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
    }

    @Test func metadataOnlyChangeIsNotADiffEntry() {
        let before = item(id: "shared")
        let after = BTMItem(
            identifier: "shared", name: "Renamed", developerName: "Other Dev",
            bundleIdentifier: "com.example.shared", teamIdentifier: "TEAMSHARED",
            type: .app, disposition: .enabled, dispositionRaw: 0x8b, scope: .system,
            modificationDate: Date(timeIntervalSince1970: 1_800_000_000),
            parentIdentifier: "2.com.example.parent"
        )
        let diff = SnapshotStore.diffBTMItems(before: [before], after: [after])
        #expect(!diff.hasContent)
    }

    // Builds before v0.7.2 stored types they could not name as `unknown` with
    // the raw value; reading one back must equal the same item scanned now,
    // or the first scan after upgrading reports every such item as changed.
    @Test func storedUnknownTypeDecodesToTheNowKnownType() async throws {
        let store = try SnapshotStore.inMemory()
        let id = try await store.writeBTMItemsSnapshot([])
        let scanned = item(id: "agent", type: .legacyAgent)
        try await store.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO btm_items
                (snapshot_id, identifier, name, developer_name, bundle_identifier,
                 team_identifier, type_kind, type_raw, disposition_kind, disposition_raw,
                 scope_kind, scope_per_user_uuid, modification_date, parent_identifier)
                VALUES (?, 'agent', 'Item-agent', 'Dev-agent', 'com.example.agent',
                        'TEAMAGENT', 'unknown', 65544, 'enabled', 0, 'system', NULL, ?, NULL)
                """, arguments: [id.rawValue, scanned.modificationDate])
        }
        let stored = try await store.readBTMItems(snapshotID: id)
        #expect(stored == [scanned])
        #expect(!SnapshotStore.diffBTMItems(before: stored, after: [scanned]).hasContent)
    }

    @Test func differentSigningTeamIsAChange() {
        let before = item(id: "helper")
        let after = signed(before, team: "OTHERTEAM1")

        let diff = SnapshotStore.diffBTMItems(before: [before], after: [after])

        #expect(diff.changed == [DomainChange(before: before, after: after)])
        #expect(diff.changed.first?.teamIdentifierChanged == true)
    }

    // A team ID one scan could not read is not a different developer.
    @Test func missingTeamOnEitherSideIsNotAChange() {
        let signedItem = item(id: "helper")
        for (before, after) in [(signed(signedItem, team: nil), signedItem), (signedItem, signed(signedItem, team: ""))] {
            #expect(!SnapshotStore.diffBTMItems(before: [before], after: [after]).hasContent)
        }
    }

    @Test func sameIdentifierInThreeScopesDiffsIndependently() {
        let perUser = BTMItem.Scope.perUser(uuid: "EBE3FCE9-AAB7-4856-9DE0-DA73CD18AAEE")
        let before = [
            item(id: "2.us.zoom.xos", scope: .system),
            item(id: "2.us.zoom.xos", scope: .user),
            item(id: "2.us.zoom.xos", scope: perUser),
        ]
        let after = [
            item(id: "2.us.zoom.xos", disposition: .disabled, scope: .system),
            item(id: "2.us.zoom.xos", scope: perUser),
        ]
        let diff = SnapshotStore.diffBTMItems(before: before, after: after)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.map(\.scope) == [.user])
        #expect(diff.changed.map(\.after.scope) == [.system])
    }

    private func signed(_ item: BTMItem, team: String?) -> BTMItem {
        BTMItem(
            identifier: item.identifier, name: item.name, developerName: item.developerName,
            bundleIdentifier: item.bundleIdentifier, teamIdentifier: team, type: item.type,
            disposition: item.disposition, scope: item.scope,
            modificationDate: item.modificationDate, parentIdentifier: item.parentIdentifier
        )
    }

    private func item(
        id identifier: String,
        type: BTMItem.ItemType = .app,
        disposition: BTMItem.Disposition = .enabled,
        scope: BTMItem.Scope = .system
    ) -> BTMItem {
        BTMItem(
            identifier: identifier,
            name: "Item-\(identifier)",
            developerName: "Dev-\(identifier)",
            bundleIdentifier: "com.example.\(identifier)",
            teamIdentifier: "TEAM\(identifier.uppercased())",
            type: type,
            disposition: disposition,
            scope: scope,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            parentIdentifier: nil
        )
    }
}
