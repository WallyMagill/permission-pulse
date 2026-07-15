import Foundation
import GRDB
import PermissionsCore

enum SnapshotV4Fixture {
    static let legacySnapshotID = SnapshotID(rawValue: 1)

    static func make(at path: String) throws {
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.create(table: "schema_version") { table in
                table.column("version", .integer).notNull()
            }
            try db.execute(sql: "INSERT INTO schema_version (version) VALUES (4)")

            try db.create(table: "snapshots") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("created_at", .double).notNull()
            }
            try db.create(table: "launch_agents") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("snapshot_id", .integer).notNull()
                    .references("snapshots", onDelete: .cascade)
                table.column("label", .text).notNull()
                table.column("source_directory", .text).notNull()
                table.column("program_path", .text)
                table.column("program_arguments_json", .text).notNull().defaults(to: "[]")
                table.column("run_at_load", .integer).notNull()
                table.column("keep_alive", .integer).notNull()
            }
            try db.create(table: "tcc_grants") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("snapshot_id", .integer).notNull()
                    .references("snapshots", onDelete: .cascade)
                table.column("service", .text).notNull()
                table.column("bundle_id", .text).notNull()
                table.column("display_name", .text).notNull()
                table.column("bundle_path", .text)
                table.column("last_modified", .double).notNull()
                table.column("automation_target", .text)
                table.column("auth_value", .integer).notNull().defaults(to: 2)
            }
            try db.create(table: "btm_items") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("snapshot_id", .integer).notNull()
                    .references("snapshots", onDelete: .cascade)
                table.column("identifier", .text).notNull()
                table.column("name", .text).notNull()
                table.column("developer_name", .text)
                table.column("bundle_identifier", .text)
                table.column("team_identifier", .text)
                table.column("type_kind", .text).notNull()
                table.column("type_raw", .integer)
                table.column("disposition_kind", .text).notNull()
                table.column("disposition_raw", .integer)
                table.column("scope_kind", .text).notNull()
                table.column("scope_per_user_uuid", .text)
                table.column("modification_date", .double).notNull()
                table.column("parent_identifier", .text)
            }

            try db.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            for identifier in ["v1", "v2", "v3", "v4"] {
                try db.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                    arguments: [identifier]
                )
            }

            let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
            try db.execute(
                sql: "INSERT INTO snapshots (id, created_at) VALUES (1, ?)",
                arguments: [capturedAt]
            )
            try db.execute(sql: """
                INSERT INTO launch_agents
                (snapshot_id, label, source_directory, program_path,
                 program_arguments_json, run_at_load, keep_alive)
                VALUES (1, 'com.example.disabled', 'userLaunchAgents',
                        '/usr/local/bin/disabled', '[\"--legacy\"]', 1, 0)
                """)
            try db.execute(sql: """
                INSERT INTO tcc_grants
                (snapshot_id, service, bundle_id, display_name, bundle_path,
                 last_modified, automation_target, auth_value)
                VALUES (1, 'microphone', 'com.example.legacy', 'Legacy App',
                        NULL, ?, NULL, 2)
                """, arguments: [capturedAt])
            try db.execute(sql: """
                INSERT INTO btm_items
                (snapshot_id, identifier, name, developer_name, bundle_identifier,
                 team_identifier, type_kind, type_raw, disposition_kind,
                 disposition_raw, scope_kind, scope_per_user_uuid,
                 modification_date, parent_identifier)
                VALUES (1, 'com.example.legacy-helper', 'Legacy Helper', NULL,
                        'com.example.legacy-helper', NULL, 'app', NULL, 'enabled',
                        0, 'user', NULL, ?, NULL)
                """, arguments: [capturedAt])
        }
    }

    static func launchAgentCaptureMarker(
        at path: String,
        snapshotID: SnapshotID
    ) throws -> Bool {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in
            let marker = try Int.fetchOne(
                db,
                sql: """
                    SELECT launch_agent_disabled_captured
                    FROM snapshots
                    WHERE id = ?
                    """,
                arguments: [snapshotID.rawValue]
            )
            return marker == 1
        }
    }
}
