import Foundation
import GRDB
import PermissionsCore

/// A schema-v6 database as the v0.7.1-era app left it: the v4 fixture plus the
/// v5/v6 columns, and a captured snapshot holding two launch agents.
enum SnapshotV6Fixture {
    static let capturedSnapshotID = SnapshotID(rawValue: 2)

    static let agents = [
        LaunchAgentItem(
            label: "com.example.updater",
            sourceDirectory: .libraryLaunchDaemons,
            programPath: "/Library/PrivilegedHelperTools/com.example.updater",
            programArguments: [],
            runAtLoad: true,
            keepAlive: true
        ),
        LaunchAgentItem(
            label: "com.example.sync",
            sourceDirectory: .userLaunchAgents,
            programPath: nil,
            programArguments: ["/usr/local/bin/sync", "--watch"],
            runAtLoad: true,
            keepAlive: false,
            isDisabled: true
        ),
    ]

    static func make(at path: String) throws {
        try SnapshotV4Fixture.make(at: path)
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: """
                ALTER TABLE launch_agents ADD COLUMN is_disabled INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE snapshots
                    ADD COLUMN launch_agent_disabled_captured INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE snapshots ADD COLUMN tcc_coverage TEXT NOT NULL DEFAULT 'complete';
                ALTER TABLE snapshots ADD COLUMN btm_coverage TEXT NOT NULL DEFAULT 'complete';
                ALTER TABLE snapshots
                    ADD COLUMN launch_agent_coverage TEXT NOT NULL DEFAULT 'complete';
                UPDATE schema_version SET version = 6;
                INSERT INTO grdb_migrations (identifier) VALUES ('v5'), ('v6');
                """)
            try db.execute(
                sql: "INSERT INTO snapshots (id, created_at, launch_agent_disabled_captured) VALUES (2, ?, 1)",
                arguments: [Date(timeIntervalSince1970: 1_700_100_000)]
            )
            for agent in agents {
                let arguments = String(decoding: try JSONEncoder().encode(agent.programArguments), as: UTF8.self)
                try db.execute(sql: """
                    INSERT INTO launch_agents
                    (snapshot_id, label, source_directory, program_path,
                     program_arguments_json, run_at_load, keep_alive, is_disabled)
                    VALUES (2, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        agent.label, agent.sourceDirectory.rawValue, agent.programPath,
                        arguments, agent.runAtLoad, agent.keepAlive, agent.isDisabled,
                    ])
            }
        }
    }
}
