import Foundation
import GRDB
import PermissionsCore

public final class SnapshotStore {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        try Self.migrate(dbQueue)
    }

    public static func inMemory() throws -> SnapshotStore {
        try SnapshotStore(path: ":memory:")
    }

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // Schema-version anchor row. Real tables (launch_agents, tcc_grants)
            // land in the v0.2.0 LaunchAgents slice and v0.3.0 TCC slice.
            try db.create(table: "schema_version") { t in
                t.column("version", .integer).notNull()
            }
            try db.execute(sql: "INSERT INTO schema_version (version) VALUES (1)")
        }
        try migrator.migrate(queue)
    }

    public func schemaVersion() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM schema_version LIMIT 1") ?? 0
        }
    }
}
