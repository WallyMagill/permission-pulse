import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct BTMScannerDirectTests {
    @Test func scanReturnsItemsForValidFixture() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeValidFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        let output = try await scanner.scan()
        let items = output.items

        #expect(items.count == 2)
        #expect(output.warnings.isEmpty)
        let identifiers = Set(items.map(\.identifier))
        #expect(identifiers == ["2.us.zoom.xos", "16.us.zoom.ZoomDaemon"])
        #expect(!identifiers.contains("Docker"))
    }

    @Test func scanFiltersDeveloperGroupsButPreservesChildren() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeValidFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        let items = try await scanner.scan().items

        let daemon = try #require(items.first { $0.identifier == "16.us.zoom.ZoomDaemon" })
        #expect(daemon.parentIdentifier == "2.us.zoom.xos")
        #expect(daemon.type == .legacyDaemon)
        let developerGroupCount = items.filter { $0.type == .developerGroup }.count
        #expect(developerGroupCount == 0)
    }

    @Test(arguments: [
        (0x2, BTMItem.ItemType.app),
        (0x10010, BTMItem.ItemType.legacyDaemon),
        (0x20, BTMItem.ItemType.developerGroup),
        (0x99, BTMItem.ItemType.unknown(rawValue: 0x99)),
    ])
    func scanMapsTypeBitmaskCorrectly(raw: Int, expected: BTMItem.ItemType) async throws {
        // mapType is the same code-path used by scan(); test the pure mapping directly so
        // the developerGroup case is not filtered out before assertion.
        #expect(BTMScannerDirect.mapType(raw) == expected)
    }

    @Test(arguments: [
        (0xb, BTMItem.Disposition.enabled),
        (0x2, BTMItem.Disposition.disabled),
        (0x0, BTMItem.Disposition.disabled),
    ])
    func scanMapsDispositionBitZero(raw: Int, expected: BTMItem.Disposition) async throws {
        #expect(BTMScannerDirect.mapDisposition(raw) == expected)
    }

    @Test func scanPicksHighestVersionSuffix() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeEmptyItemsDictFixture(at: dir.url, fileName: "BackgroundItems-v13.btm")
        try BTMFixtures.makeSingleItemFixture(
            at: dir.url,
            fileName: "BackgroundItems-v16.btm",
            type: BTMFixtures.ItemTypeRaw.app
        )

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        let items = try await scanner.scan().items

        #expect(items.count == 1)
        #expect(items.first?.identifier == "1.test.item")
    }

    @Test func scanThrowsSchemaMismatchOnMissingTopLevelKey() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeMissingTopLevelKeyFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        do {
            _ = try await scanner.scan()
            Issue.record("Expected scan to throw")
        } catch let error as ScannerError {
            guard case .schemaMismatch = error else {
                Issue.record("Expected .schemaMismatch, got \(error)")
                return
            }
        }
    }

    @Test func scanThrowsSchemaMismatchOnMalformedFile() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeMalformedFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        do {
            _ = try await scanner.scan()
            Issue.record("Expected scan to throw")
        } catch let error as ScannerError {
            guard case .schemaMismatch = error else {
                Issue.record("Expected .schemaMismatch, got \(error)")
                return
            }
        }
    }

    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
    func scanThrowsPermissionDeniedWhenUnreadable() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeValidFixture(at: dir.url)
        let fileURL = dir.url.appendingPathComponent(BTMFixtures.defaultFileName)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: fileURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: fileURL.path
            )
        }

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        do {
            _ = try await scanner.scan()
            Issue.record("Expected scan to throw")
        } catch let error as ScannerError {
            guard case .permissionDenied = error else {
                Issue.record("Expected .permissionDenied, got \(error)")
                return
            }
        }
    }

    @Test func scanReturnsEmptyForFileWithEmptyItemsDict() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeEmptyItemsDictFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        let items = try await scanner.scan().items

        #expect(items.isEmpty)
    }

    @Test func scanIsDeterministicallyOrdered() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeValidFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        let first = try await scanner.scan().items
        let second = try await scanner.scan().items

        #expect(first == second)
    }

    @Test func scanAttributesSentinelUUIDsToCorrectScope() async throws {
        let dir = try BTMTempDir()
        try BTMFixtures.makeSentinelScopesFixture(at: dir.url)

        let scanner = BTMScannerDirect(directoryURL: dir.url)
        let items = try await scanner.scan().items

        let byIdentifier = Dictionary(uniqueKeysWithValues: items.map { ($0.identifier, $0) })
        let system = try #require(byIdentifier["system.item"])
        let root = try #require(byIdentifier["root.item"])
        let user = try #require(byIdentifier["user.item"])

        #expect(system.scope == .system)
        #expect(root.scope == .user)
        guard case .perUser(let uuid) = user.scope else {
            Issue.record("Expected .perUser, got \(user.scope)")
            return
        }
        #expect(uuid == BTMFixtures.perUserUUID)
    }
}
