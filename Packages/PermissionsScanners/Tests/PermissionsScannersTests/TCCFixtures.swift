import Foundation
import GRDB

enum TCCFixtures {
    enum AuthValue {
        static let denied = 0
        static let unknown = 1
        static let allowed = 2
        static let limited = 3
    }

    enum ClientType {
        static let bundleID = 0
        static let path = 1
    }

    static let fullSchema = """
        CREATE TABLE access (
            service TEXT NOT NULL,
            client TEXT NOT NULL,
            client_type INTEGER NOT NULL,
            auth_value INTEGER NOT NULL,
            last_modified INTEGER NOT NULL,
            indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED'
        )
        """

    static let insertSQLWithTarget = """
        INSERT INTO access (service, client, client_type, auth_value, last_modified, indirect_object_identifier)
        VALUES (?, ?, ?, ?, ?, ?)
        """

    static let schemaMissingAuthValue = """
        CREATE TABLE access (
            service TEXT NOT NULL,
            client TEXT NOT NULL,
            client_type INTEGER NOT NULL,
            last_modified INTEGER NOT NULL
        )
        """

    static let insertSQL = """
        INSERT INTO access (service, client, client_type, auth_value, last_modified)
        VALUES (?, ?, ?, ?, ?)
        """

    static let insertSQLNoAuthValue = """
        INSERT INTO access (service, client, client_type, last_modified)
        VALUES (?, ?, ?, ?)
        """

    static func makeValidFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceScreenCapture", "us.zoom.xos",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceAccessibility", "com.raycast.macos",
                ClientType.bundleID, AuthValue.allowed, 1_714_000_000,
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceSystemPolicyAllFiles", "com.apple.Terminal",
                ClientType.bundleID, AuthValue.allowed, 1_713_000_000,
            ])
        }
    }

    static func makeMissingColumnFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: schemaMissingAuthValue) { db in
            try db.execute(sql: insertSQLNoAuthValue, arguments: [
                "kTCCServiceCamera", "com.example.app",
                ClientType.bundleID, 1_715_000_000,
            ])
        }
    }

    static func makeUnknownServiceFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.valid",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceFutureThing", "com.example.future",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
        }
    }

    static func makeSkippedServiceFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceLiverpool", "com.apple.Home",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
        }
    }

    static func makeEmptyFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { _ in }
    }

    /// SQLite type affinity is advisory — a TCC.db cell can hold any storage
    /// class regardless of the declared column type. Rows with anomalous
    /// storage must be dropped or defaulted, never crash the scan.
    static func makeWrongTypedFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            // service stored as a non-UTF8 BLOB — row must be dropped.
            try db.execute(sql: insertSQL, arguments: [
                Data([0x80, 0x81]), "com.example.blob-service",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
            // client_type stored as non-numeric TEXT — decodes as nil and the
            // row is dropped by identity mapping, not a crash.
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.text-client-type",
                "not-a-number", AuthValue.allowed, 1_715_000_000,
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceMicrophone", "com.example.valid",
                ClientType.bundleID, AuthValue.allowed, 1_714_000_000,
            ])
        }
    }

    static func makeMultiGrantFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceScreenCapture", "us.zoom.xos",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceMicrophone", "us.zoom.xos",
                ClientType.bundleID, AuthValue.allowed, 1_714_000_000,
            ])
        }
    }

    static func makeAutomationFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQLWithTarget, arguments: [
                "kTCCServiceAppleEvents", "com.raycast.macos",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
                "com.apple.Safari",
            ])
            try db.execute(sql: insertSQLWithTarget, arguments: [
                "kTCCServiceAppleEvents", "com.raycast.macos",
                ClientType.bundleID, AuthValue.allowed, 1_714_000_000,
                "com.googlecode.iterm2",
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.app",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
        }
    }

    static func makeNonexistentBundleFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.permissionpulse.nonexistent-test.bundle",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
        }
    }

    // Identical grant (same service + client + client_type) at a specific
    // last_modified. Used by the dedupe test to seed two databases that
    // collide except for the timestamp.
    static func makeTimestampedFixture(url: URL, lastModified: Int) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.dup",
                ClientType.bundleID, AuthValue.allowed, lastModified,
            ])
        }
    }

    static func makeDeniedFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.denied",
                ClientType.bundleID, AuthValue.denied, 1_715_000_000,
            ])
        }
    }

    // One limited-access Photos row (auth_value = 3) plus one standard
    // allowed row. Used by the D2 scanner test to verify limited rows are
    // returned with their auth_value preserved.
    static func makeLimitedAccessFixture(url: URL) async throws {
        try await makeFixture(url: url, schema: fullSchema) { db in
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServicePhotos", "com.example.photoapp",
                ClientType.bundleID, AuthValue.limited, 1_715_000_000,
            ])
            try db.execute(sql: insertSQL, arguments: [
                "kTCCServiceCamera", "com.example.cameraapp",
                ClientType.bundleID, AuthValue.allowed, 1_715_000_000,
            ])
        }
    }

    private static func makeFixture(
        url: URL,
        schema: String,
        body: @Sendable (Database) throws -> Void
    ) async throws {
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false))
        try await queue.write { db in
            try db.execute(sql: schema)
            try body(db)
        }
    }
}
