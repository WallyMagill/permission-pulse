import Foundation
@testable import PermissionsScanners

enum BTMFixtures {
    enum ItemTypeRaw {
        static let app = 0x2
        static let developerGroup = 0x20
        static let legacyDaemon = 0x10010
    }

    enum DispositionRaw {
        static let enabledAllowedNotified = 0xb
        static let disabledAllowedNotNotified = 0x2
        static let zero = 0x0
    }

    static let rootUserUUID = "FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE"
    static let systemUserUUID = "FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000"
    static let perUserUUID = "341C3E9C-EE6A-47A0-96B3-1BAA3991B529"

    static let defaultFileName = "BackgroundItems-v16.btm"

    static let zoomApp = BTMItemRecordShim(
        identifier: "2.us.zoom.xos",
        name: "zoom.us",
        developerName: nil,
        bundleIdentifier: "us.zoom.xos",
        teamIdentifier: "BJ4HAAB9B3",
        container: nil,
        type: ItemTypeRaw.app,
        disposition: DispositionRaw.disabledAllowedNotNotified,
        modificationDate: 782_917_665.899524
    )

    static let zoomDaemon = BTMItemRecordShim(
        identifier: "16.us.zoom.ZoomDaemon",
        name: "us.zoom.ZoomDaemon",
        developerName: "Zoom Video Communications, Inc.",
        bundleIdentifier: nil,
        teamIdentifier: "BJ4HAAB9B3",
        container: "2.us.zoom.xos",
        type: ItemTypeRaw.legacyDaemon,
        disposition: DispositionRaw.enabledAllowedNotified,
        modificationDate: 782_917_666.624119
    )

    static let dockerGroup = BTMItemRecordShim(
        identifier: "Docker",
        name: "Docker",
        developerName: "Docker",
        bundleIdentifier: nil,
        teamIdentifier: nil,
        container: nil,
        type: ItemTypeRaw.developerGroup,
        disposition: DispositionRaw.disabledAllowedNotNotified,
        modificationDate: 782_917_660.0
    )

    static func makeValidFixture(at directory: URL, fileName: String = defaultFileName) throws {
        let items: NSDictionary = [
            rootUserUUID: NSArray(array: [zoomApp, dockerGroup]),
            perUserUUID: NSArray(array: [zoomDaemon]),
        ]
        let storage = BTMStorageShim(itemsByUserIdentifier: items)
        try writeArchive(storage: storage, to: directory.appendingPathComponent(fileName))
    }

    static func makeSingleItemFixture(
        at directory: URL,
        fileName: String = defaultFileName,
        type: Int,
        disposition: Int = DispositionRaw.enabledAllowedNotified
    ) throws {
        let item = BTMItemRecordShim(
            identifier: "1.test.item",
            name: "Test Item",
            developerName: "Test Dev",
            bundleIdentifier: "com.test.item",
            teamIdentifier: "TESTTEAM01",
            container: nil,
            type: type,
            disposition: disposition,
            modificationDate: 782_917_666.0
        )
        let items: NSDictionary = [
            rootUserUUID: NSArray(array: [item]),
        ]
        let storage = BTMStorageShim(itemsByUserIdentifier: items)
        try writeArchive(storage: storage, to: directory.appendingPathComponent(fileName))
    }

    static func makeEmptyItemsDictFixture(
        at directory: URL,
        fileName: String = defaultFileName
    ) throws {
        let storage = BTMStorageShim(itemsByUserIdentifier: NSDictionary())
        try writeArchive(storage: storage, to: directory.appendingPathComponent(fileName))
    }

    /// Writes an archive whose `Storage` object has no `itemsByUserIdentifier`
    /// field — simulates a future macOS release that renames the property.
    static func makeMissingTopLevelKeyFixture(
        at directory: URL,
        fileName: String = defaultFileName
    ) throws {
        let storage = BTMStorageShim(itemsByUserIdentifier: nil)
        try writeArchive(storage: storage, to: directory.appendingPathComponent(fileName))
    }

    static func makeMalformedFixture(
        at directory: URL,
        fileName: String = defaultFileName
    ) throws {
        try Data().write(to: directory.appendingPathComponent(fileName))
    }

    static func makeSentinelScopesFixture(at directory: URL, fileName: String = defaultFileName) throws {
        let systemItem = BTMItemRecordShim(
            identifier: "system.item",
            name: "System Item",
            type: ItemTypeRaw.legacyDaemon,
            disposition: DispositionRaw.enabledAllowedNotified,
            modificationDate: 782_917_666.0
        )
        let rootItem = BTMItemRecordShim(
            identifier: "root.item",
            name: "Root Item",
            type: ItemTypeRaw.app,
            disposition: DispositionRaw.enabledAllowedNotified,
            modificationDate: 782_917_666.0
        )
        let userItem = BTMItemRecordShim(
            identifier: "user.item",
            name: "User Item",
            type: ItemTypeRaw.app,
            disposition: DispositionRaw.enabledAllowedNotified,
            modificationDate: 782_917_666.0
        )
        let items: NSDictionary = [
            systemUserUUID: NSArray(array: [systemItem]),
            rootUserUUID: NSArray(array: [rootItem]),
            perUserUUID: NSArray(array: [userItem]),
        ]
        let storage = BTMStorageShim(itemsByUserIdentifier: items)
        try writeArchive(storage: storage, to: directory.appendingPathComponent(fileName))
    }

    private static func writeArchive(storage: BTMStorageShim, to url: URL) throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.outputFormat = .binary
        archiver.setClassName(BTMScannerDirect.storageClassName, for: BTMStorageShim.self)
        archiver.setClassName(BTMScannerDirect.itemRecordClassName, for: BTMItemRecordShim.self)
        archiver.encode(storage, forKey: BTMScannerDirect.topLevelStoreKey)
        archiver.finishEncoding()
        try archiver.encodedData.write(to: url)
    }
}
