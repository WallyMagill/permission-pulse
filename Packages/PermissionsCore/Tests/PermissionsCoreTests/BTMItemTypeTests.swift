import Foundation
import Testing
@testable import PermissionsCore

@Suite struct BTMItemTypeTests {
    @Test(arguments: [
        (0x2, BTMItem.ItemType.app),
        (0x4, .loginItem),
        (0x8, .agent),
        (0x20, .developerGroup),
        (0x40, .spotlightImporter),
        (0x80, .dockTilePlugin),
        (0x800, .quickLookExtension),
        (0x2000, .backgroundTasks),
        (0x10008, .legacyAgent),
        (0x10010, .legacyDaemon),
        (0x99, .unknown(rawValue: 0x99)),
    ])
    func rawValueMapsToTypeAndBack(raw: Int, expected: BTMItem.ItemType) {
        let type = BTMItem.ItemType(rawValue: raw)
        #expect(type == expected)
        #expect(type.rawValue == raw)
        #expect(BTMItem.ItemType(kindName: type.kindName) == (raw == 0x99 ? nil : type))
    }

    @Test func identitySeparatesScopesOfTheSameIdentifier() {
        func item(_ scope: BTMItem.Scope) -> BTMItem {
            BTMItem(identifier: "2.us.zoom.xos", name: "zoom.us", type: .app,
                    disposition: .enabled, scope: scope, modificationDate: .distantPast)
        }
        let ids = [item(.system), item(.user), item(.perUser(uuid: "A")), item(.perUser(uuid: "B"))].map(\.id)
        #expect(Set(ids).count == 4)
        #expect(ids[0] == "system|2.us.zoom.xos")
    }
}
