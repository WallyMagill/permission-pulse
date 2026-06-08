import Foundation
import Testing
import PermissionsCore
@testable import PermissionsStore

@Suite struct BTMDiffTests {
    @Test func migrationV3CreatesBTMItemsTable() async throws {
        let store = try SnapshotStore.inMemory()
        #expect(try store.schemaVersion() == 4)
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
