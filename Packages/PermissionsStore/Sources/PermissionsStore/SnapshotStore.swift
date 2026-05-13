import Foundation
import GRDB
import PermissionsCore

public struct SnapshotStore: Sendable {
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
            try db.create(table: "schema_version") { t in
                t.column("version", .integer).notNull()
            }
            try db.execute(sql: "INSERT INTO schema_version (version) VALUES (1)")
        }

        migrator.registerMigration("v2") { db in
            try db.create(table: "snapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .double).notNull()
            }
            try db.create(table: "launch_agents") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("snapshot_id", .integer).notNull()
                    .references("snapshots", onDelete: .cascade)
                t.column("label", .text).notNull()
                t.column("source_directory", .text).notNull()
                t.column("program_path", .text)
                t.column("program_arguments_json", .text).notNull().defaults(to: "[]")
                t.column("run_at_load", .integer).notNull()
                t.column("keep_alive", .integer).notNull()
            }
            try db.execute(sql: "UPDATE schema_version SET version = 2")
        }

        try migrator.migrate(queue)
    }

    public func schemaVersion() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM schema_version LIMIT 1") ?? 0
        }
    }

    public func writeLaunchAgentsSnapshot(
        _ items: [LaunchAgentItem],
        at date: Date = Date()
    ) async throws -> SnapshotID {
        try await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO snapshots (created_at) VALUES (?)",
                arguments: [date]
            )
            let snapshotRowID = db.lastInsertedRowID

            for item in items {
                let argsJSON = try Self.encodeArguments(item.programArguments)
                try db.execute(sql: """
                    INSERT INTO launch_agents
                    (snapshot_id, label, source_directory, program_path,
                     program_arguments_json, run_at_load, keep_alive)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        snapshotRowID,
                        item.label,
                        item.sourceDirectory.rawValue,
                        item.programPath,
                        argsJSON,
                        item.runAtLoad,
                        item.keepAlive,
                    ])
            }

            return SnapshotID(rawValue: snapshotRowID)
        }
    }

    public func readLaunchAgents(snapshotID: SnapshotID) async throws -> [LaunchAgentItem] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT label, source_directory, program_path,
                       program_arguments_json, run_at_load, keep_alive
                FROM launch_agents
                WHERE snapshot_id = ?
                ORDER BY source_directory, label
                """, arguments: [snapshotID.rawValue])
            return try rows.map(Self.itemFromRow)
        }
    }

    public func diffLaunchAgents(
        from: SnapshotID,
        to: SnapshotID
    ) async throws -> LaunchAgentsDiff {
        let before = try await readLaunchAgents(snapshotID: from)
        let after = try await readLaunchAgents(snapshotID: to)
        let beforeKeys = Set(before.map(Self.identityKey))
        let afterKeys = Set(after.map(Self.identityKey))
        let added = after.filter { !beforeKeys.contains(Self.identityKey($0)) }
        let removed = before.filter { !afterKeys.contains(Self.identityKey($0)) }
        return LaunchAgentsDiff(added: added, removed: removed)
    }

    private static func identityKey(_ item: LaunchAgentItem) -> String {
        "\(item.sourceDirectory.rawValue)|\(item.label)"
    }

    private static func encodeArguments(_ args: [String]) throws -> String {
        let data = try JSONEncoder().encode(args)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeArguments(_ json: String) throws -> [String] {
        let data = Data(json.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }

    private static func itemFromRow(_ row: Row) throws -> LaunchAgentItem {
        let label: String = row["label"]
        let sourceRaw: String = row["source_directory"]
        guard let source = LaunchAgentItem.SourceDirectory(rawValue: sourceRaw) else {
            throw StoreError.unknownSourceDirectory(sourceRaw)
        }
        let argsJSON: String = row["program_arguments_json"]
        let arguments = try decodeArguments(argsJSON)
        return LaunchAgentItem(
            label: label,
            sourceDirectory: source,
            programPath: row["program_path"],
            programArguments: arguments,
            runAtLoad: row["run_at_load"],
            keepAlive: row["keep_alive"]
        )
    }
}

public enum StoreError: Error, Sendable {
    case unknownSourceDirectory(String)
}
