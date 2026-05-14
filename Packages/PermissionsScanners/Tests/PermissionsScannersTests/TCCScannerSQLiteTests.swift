import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct TCCScannerSQLiteTests {
    @Test func scanReturnsGrantsForValidFixture() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("user.db")
        try await TCCFixtures.makeValidFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let grants = try await scanner.scan()

        #expect(grants.count == 3)
        let bundleIDs = Set(grants.map(\.app.bundleID))
        #expect(bundleIDs == ["us.zoom.xos", "com.raycast.macos", "com.apple.Terminal"])
        let services = Set(grants.map(\.service))
        #expect(services == [.screenRecording, .accessibility, .fullDiskAccess])
    }

    @Test func scanUnionsResultsFromMultipleFixtures() async throws {
        let dir = try TempDir()
        let userDB = dir.dbURL("user.db")
        let systemDB = dir.dbURL("system.db")
        try await TCCFixtures.makeMultiGrantFixture(url: userDB)
        try await TCCFixtures.makeValidFixture(url: systemDB)

        let scanner = TCCScannerSQLite(databaseURLs: [userDB, systemDB])
        let grants = try await scanner.scan()

        #expect(grants.count == 5)
    }

    @Test func scanThrowsSchemaMismatchWhenColumnMissing() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("missing.db")
        try await TCCFixtures.makeMissingColumnFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
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
    func scanThrowsPermissionDeniedWhenFileUnreadable() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("unreadable.db")
        try await TCCFixtures.makeValidFixture(url: dbURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: dbURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: dbURL.path
            )
        }

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
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

    @Test func scanSkipsUnknownServices() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("unknown.db")
        try await TCCFixtures.makeUnknownServiceFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let grants = try await scanner.scan()

        #expect(grants.count == 1)
        #expect(grants.first?.app.bundleID == "com.example.valid")
    }

    @Test func scanSkipsKnownSkippedServices() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("skipped.db")
        try await TCCFixtures.makeSkippedServiceFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let grants = try await scanner.scan()

        #expect(grants.isEmpty)
    }

    @Test func scanReturnsEmptyForEmptyTable() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("empty.db")
        try await TCCFixtures.makeEmptyFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let grants = try await scanner.scan()

        #expect(grants.isEmpty)
    }

    @Test func scanReturnsMultipleGrantsForSameApp() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("multi.db")
        try await TCCFixtures.makeMultiGrantFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let grants = try await scanner.scan()

        #expect(grants.count == 2)
        #expect(grants.allSatisfy { $0.app.bundleID == "us.zoom.xos" })
        let services = Set(grants.map(\.service))
        #expect(services == [.screenRecording, .microphone])
    }

    @Test func scanSkipsDeniedGrants() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("denied.db")
        try await TCCFixtures.makeDeniedFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let grants = try await scanner.scan()

        #expect(grants.isEmpty)
    }

    @Test func scanIsDeterministicallyOrdered() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("ordered.db")
        try await TCCFixtures.makeValidFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        let first = try await scanner.scan()
        let second = try await scanner.scan()

        #expect(first == second)
    }

    @Test func scanLogsErrorWhenOneDBFailsAndReturnsOther() async throws {
        let dir = try TempDir()
        let validURL = dir.dbURL("valid.db")
        let missingURL = dir.dbURL("missing.db")
        try await TCCFixtures.makeValidFixture(url: validURL)

        let scanner = TCCScannerSQLite(databaseURLs: [validURL, missingURL])
        let grants = try await scanner.scan()

        #expect(grants.count == 3)
    }

    @Test func scanThrowsWhenBothDBsFail() async throws {
        let dir = try TempDir()
        let missing1 = dir.dbURL("a.db")
        let missing2 = dir.dbURL("b.db")

        let scanner = TCCScannerSQLite(databaseURLs: [missing1, missing2])
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

    @Test func scanDoesNotCreateSidecarFiles() async throws {
        let dir = try TempDir()
        let dbURL = dir.dbURL("sidecars.db")
        try await TCCFixtures.makeValidFixture(url: dbURL)

        let scanner = TCCScannerSQLite(databaseURLs: [dbURL])
        _ = try await scanner.scan()

        let walURL = dir.url.appendingPathComponent("sidecars.db-wal")
        let shmURL = dir.url.appendingPathComponent("sidecars.db-shm")
        #expect(!FileManager.default.fileExists(atPath: walURL.path))
        #expect(!FileManager.default.fileExists(atPath: shmURL.path))
    }
}

private final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ppulse-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func dbURL(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}
