import Foundation
import Testing
@testable import PermissionsScanners

@Suite struct BTMFixturesRoundTripTests {
    @Test func validFixtureRoundTripsThroughNSKeyedArchiver() throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeValidFixture(at: dir.url)

        let fileURL = dir.url.appendingPathComponent(BTMFixtures.defaultFileName)
        let data = try Data(contentsOf: fileURL)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(BTMStorageShim.self, forClassName: BTMScannerDirect.storageClassName)
        unarchiver.setClass(BTMItemRecordShim.self, forClassName: BTMScannerDirect.itemRecordClassName)

        let storage = try #require(
            unarchiver.decodeObject(forKey: BTMScannerDirect.topLevelStoreKey) as? BTMStorageShim
        )
        let items = try #require(storage.itemsByUserIdentifier)
        let rootBucket = try #require(items[BTMFixtures.rootUserUUID] as? [BTMItemRecordShim])
        #expect(rootBucket.count == 2)

        let zoomApp = try #require(rootBucket.first { $0.identifier == "2.us.zoom.xos" })
        #expect(zoomApp.name == "zoom.us")
        #expect(zoomApp.teamIdentifier == "BJ4HAAB9B3")
        #expect(zoomApp.bundleIdentifier == "us.zoom.xos")
        #expect(zoomApp.type == 0x2)
    }
}

final class BTMTempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ppulse-btm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
