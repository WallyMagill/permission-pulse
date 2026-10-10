import Foundation
import GRDB
import OSLog
import PermissionsCore

public struct SnapshotStore: Sendable {
    static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "snapshot-store"
    )

    let dbQueue: DatabaseQueue

    public init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        try Self.migrate(dbQueue)
    }

    public static func inMemory() throws -> SnapshotStore {
        try SnapshotStore(path: ":memory:")
    }

    // INVARIANT: every `.double`-declared date column (created_at, last_modified,
    // modification_date) actually stores a GRDB-encoded fixed-width TEXT date,
    // NOT a numeric timestamp. Comparisons (ORDER BY created_at, created_at <= ?)
    // rely on lexicographic ordering of that fixed format. Only ever write these
    // via a Swift `Date` through GRDB — a raw numeric write would make SQLite sort
    // all REALs before all TEXT and silently corrupt ordering/pruning. Pinned by
    // SnapshotDateEncodingTests. (D5)
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

        migrator.registerMigration("v3") { db in
            try db.create(table: "tcc_grants") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("snapshot_id", .integer).notNull()
                    .references("snapshots", onDelete: .cascade)
                t.column("service", .text).notNull()
                t.column("bundle_id", .text).notNull()
                t.column("display_name", .text).notNull()
                t.column("bundle_path", .text)
                t.column("last_modified", .double).notNull()
                t.column("automation_target", .text)
            }
            try db.create(table: "btm_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("snapshot_id", .integer).notNull()
                    .references("snapshots", onDelete: .cascade)
                t.column("identifier", .text).notNull()
                t.column("name", .text).notNull()
                t.column("developer_name", .text)
                t.column("bundle_identifier", .text)
                t.column("team_identifier", .text)
                t.column("type_kind", .text).notNull()
                t.column("type_raw", .integer)
                t.column("disposition_kind", .text).notNull()
                t.column("disposition_raw", .integer)
                t.column("scope_kind", .text).notNull()
                t.column("scope_per_user_uuid", .text)
                t.column("modification_date", .double).notNull()
                t.column("parent_identifier", .text)
            }
            try db.execute(sql: "UPDATE schema_version SET version = 3")
        }

        migrator.registerMigration("v4") { db in
            try db.alter(table: "tcc_grants") { t in
                t.add(column: "auth_value", .integer).notNull().defaults(to: 2)
            }
            try db.execute(sql: "UPDATE schema_version SET version = 4")
        }

        migrator.registerMigration("v5") { db in
            try db.alter(table: "launch_agents") { table in
                table.add(column: "is_disabled", .integer).notNull().defaults(to: false)
            }
            try db.alter(table: "snapshots") { table in
                table.add(column: "launch_agent_disabled_captured", .integer)
                    .notNull()
                    .defaults(to: false)
            }
            try db.execute(sql: "UPDATE schema_version SET version = 5")
        }

        // Before v6 only fully complete scans were written, so existing rows
        // are truthfully `complete`.
        migrator.registerMigration("v6") { db in
            try db.alter(table: "snapshots") { table in
                for column in ["tcc_coverage", "btm_coverage", "launch_agent_coverage"] {
                    table.add(column: column, .text)
                        .notNull()
                        .defaults(to: SnapshotCoverage.complete.rawValue)
                }
            }
            try db.execute(sql: "UPDATE schema_version SET version = 6")
        }

        try migrator.migrate(queue)
    }

    public func schemaVersion() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT version FROM schema_version LIMIT 1") ?? 0
        }
    }

    // MARK: - Writes

    // Production entry point. Writes one snapshots row plus the child rows of
    // every domain that did not fail, in a single transaction.
    public func writeSnapshot(
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        coverage: SnapshotDomainCoverage,
        at date: Date = Date()
    ) async throws -> SnapshotID {
        try await dbQueue.write { db in
            let snapshotRowID = try Self.insertSnapshot(db: db, date: date, coverage: coverage)
            if coverage.launchAgents != .failed {
                try Self.insertLaunchAgents(db: db, snapshotID: snapshotRowID, items: launchAgents)
            }
            if coverage.tcc != .failed {
                try Self.insertTCCGrants(db: db, snapshotID: snapshotRowID, grants: grants)
            }
            if coverage.btm != .failed {
                try Self.insertBTMItems(db: db, snapshotID: snapshotRowID, items: btmItems)
            }
            return SnapshotID(rawValue: snapshotRowID)
        }
    }

    public func writeFullSnapshot(
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        at date: Date = Date()
    ) async throws -> SnapshotID {
        try await writeSnapshot(
            grants: grants,
            launchAgents: launchAgents,
            btmItems: btmItems,
            coverage: .allComplete,
            at: date
        )
    }

    // Test helper — production path is writeFullSnapshot.
    public func writeLaunchAgentsSnapshot(
        _ items: [LaunchAgentItem],
        at date: Date = Date()
    ) async throws -> SnapshotID {
        try await dbQueue.write { db in
            let snapshotRowID = try Self.insertSnapshot(db: db, date: date)
            try Self.insertLaunchAgents(db: db, snapshotID: snapshotRowID, items: items)
            return SnapshotID(rawValue: snapshotRowID)
        }
    }

    // Test helper — production path is writeFullSnapshot.
    public func writeTCCGrantsSnapshot(
        _ grants: [PermissionGrant],
        at date: Date = Date()
    ) async throws -> SnapshotID {
        try await dbQueue.write { db in
            let snapshotRowID = try Self.insertSnapshot(db: db, date: date)
            try Self.insertTCCGrants(db: db, snapshotID: snapshotRowID, grants: grants)
            return SnapshotID(rawValue: snapshotRowID)
        }
    }

    // Test helper — production path is writeFullSnapshot.
    public func writeBTMItemsSnapshot(
        _ items: [BTMItem],
        at date: Date = Date()
    ) async throws -> SnapshotID {
        try await dbQueue.write { db in
            let snapshotRowID = try Self.insertSnapshot(db: db, date: date)
            try Self.insertBTMItems(db: db, snapshotID: snapshotRowID, items: items)
            return SnapshotID(rawValue: snapshotRowID)
        }
    }

    // MARK: - Reads

    public func readLaunchAgents(snapshotID: SnapshotID) async throws -> [LaunchAgentItem] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT label, source_directory, program_path,
                       program_arguments_json, run_at_load, keep_alive, is_disabled
                FROM launch_agents
                WHERE snapshot_id = ?
                ORDER BY source_directory, label
                """, arguments: [snapshotID.rawValue])
            return try rows.map(Self.launchAgentFromRow)
        }
    }

    public func readTCCGrants(snapshotID: SnapshotID) async throws -> [PermissionGrant] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT service, bundle_id, display_name, bundle_path,
                       last_modified, automation_target, auth_value
                FROM tcc_grants
                WHERE snapshot_id = ?
                ORDER BY service, bundle_id, automation_target
                """, arguments: [snapshotID.rawValue])
            return try rows.map(Self.tccGrantFromRow)
        }
    }

    public func readBTMItems(snapshotID: SnapshotID) async throws -> [BTMItem] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT identifier, name, developer_name, bundle_identifier,
                       team_identifier, type_kind, type_raw, disposition_kind,
                       disposition_raw, scope_kind, scope_per_user_uuid,
                       modification_date, parent_identifier
                FROM btm_items
                WHERE snapshot_id = ?
                ORDER BY identifier
                """, arguments: [snapshotID.rawValue])
            return try rows.map(Self.btmItemFromRow)
        }
    }

    // MARK: - Snapshot metadata

    public func coverage(snapshotID: SnapshotID) async throws -> SnapshotDomainCoverage {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT tcc_coverage, btm_coverage, launch_agent_coverage
                FROM snapshots WHERE id = ?
                """, arguments: [snapshotID.rawValue]) else {
                throw StoreError.snapshotNotFound(snapshotID.rawValue)
            }
            return SnapshotDomainCoverage(
                tcc: Self.decodeCoverage(row["tcc_coverage"]),
                btm: Self.decodeCoverage(row["btm_coverage"]),
                launchAgents: Self.decodeCoverage(row["launch_agent_coverage"])
            )
        }
    }

    public func snapshotDate(snapshotID: SnapshotID) async throws -> Date? {
        try await dbQueue.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT created_at FROM snapshots WHERE id = ?",
                arguments: [snapshotID.rawValue]
            )
        }
    }

    // An unrecognized value (e.g. written by a newer build) must never let a
    // diff compare uncertain evidence, so it reads as `.failed`.
    private static func decodeCoverage(_ raw: String) -> SnapshotCoverage {
        if let coverage = SnapshotCoverage(rawValue: raw) { return coverage }
        logger.error("Unknown snapshot coverage value \(raw, privacy: .public); treating as failed")
        return .failed
    }

    // MARK: - Discovery + retention

    public func latestSnapshotID() async throws -> SnapshotID? {
        try await dbQueue.read { db in
            // Order by created_at primarily so out-of-order inserts (test
            // seeding, restored backups, manual sqlite edits) resolve to
            // the actually-most-recent snapshot. Fall back to id for the
            // degenerate tie case (two snapshots at the same instant —
            // impossible in production but worth being deterministic).
            try Int64.fetchOne(db, sql: """
                SELECT id FROM snapshots
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """)
                .map(SnapshotID.init(rawValue:))
        }
    }

    public func latestSnapshotID(atOrBefore cutoff: Date) async throws -> SnapshotID? {
        try await dbQueue.read { db in
            try Int64.fetchOne(db, sql: """
                SELECT id FROM snapshots
                WHERE created_at <= ?
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """, arguments: [cutoff])
                .map(SnapshotID.init(rawValue:))
        }
    }

    /// Deletes snapshots older than `cutoff`, except the newest one at or before
    /// it (snapshots are written only on change, so that row *is* the state at
    /// the cutoff) and the overall latest.
    @discardableResult
    public func pruneSnapshots(olderThan cutoff: Date) async throws -> Int {
        try await dbQueue.write { db in
            let baselineID = try Int64.fetchOne(db, sql: """
                SELECT id FROM snapshots WHERE created_at <= ?
                ORDER BY created_at DESC, id DESC LIMIT 1
                """, arguments: [cutoff])
            let latestID = try Int64.fetchOne(db, sql: """
                SELECT id FROM snapshots ORDER BY created_at DESC, id DESC LIMIT 1
                """)
            try db.execute(
                sql: "DELETE FROM snapshots WHERE created_at < ? AND id NOT IN (?, ?)",
                arguments: [cutoff, baselineID ?? -1, latestID ?? -1]
            )
            return db.changesCount
        }
    }

    // Test-only helper: count rows in each child table directly. Lets retention
    // tests verify FK CASCADE behavior without trusting the public read methods.
    internal func unsafeChildRowCounts() async throws -> (tcc: Int, btm: Int, la: Int) {
        try await dbQueue.read { db in
            let tcc = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tcc_grants") ?? 0
            let btm = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM btm_items") ?? 0
            let la  = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM launch_agents") ?? 0
            return (tcc, btm, la)
        }
    }

    // MARK: - Private write helpers

    private static func insertSnapshot(
        db: Database,
        date: Date,
        coverage: SnapshotDomainCoverage = .allComplete
    ) throws -> Int64 {
        try db.execute(
            sql: """
                INSERT INTO snapshots
                (created_at, launch_agent_disabled_captured,
                 tcc_coverage, btm_coverage, launch_agent_coverage)
                VALUES (?, 1, ?, ?, ?)
                """,
            arguments: [
                date,
                coverage.tcc.rawValue,
                coverage.btm.rawValue,
                coverage.launchAgents.rawValue,
            ]
        )
        return db.lastInsertedRowID
    }

    private static func insertLaunchAgents(
        db: Database,
        snapshotID: Int64,
        items: [LaunchAgentItem]
    ) throws {
        for item in items {
            let argsJSON = try encodeArguments(item.programArguments)
            try db.execute(sql: """
                INSERT INTO launch_agents
                (snapshot_id, label, source_directory, program_path,
                 program_arguments_json, run_at_load, keep_alive, is_disabled)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    snapshotID,
                    item.label,
                    item.sourceDirectory.rawValue,
                    item.programPath,
                    argsJSON,
                    item.runAtLoad,
                    item.keepAlive,
                    item.isDisabled,
                ])
        }
    }

    private static func insertTCCGrants(
        db: Database,
        snapshotID: Int64,
        grants: [PermissionGrant]
    ) throws {
        for grant in grants {
            try db.execute(sql: """
                INSERT INTO tcc_grants
                (snapshot_id, service, bundle_id, display_name, bundle_path,
                 last_modified, automation_target, auth_value)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    snapshotID,
                    grant.service.rawValue,
                    grant.app.bundleID,
                    grant.app.displayName,
                    grant.app.bundlePath?.path(percentEncoded: false),
                    grant.lastModified,
                    grant.automationTarget,
                    grant.authValue,
                ])
        }
    }

    private static func insertBTMItems(
        db: Database,
        snapshotID: Int64,
        items: [BTMItem]
    ) throws {
        for item in items {
            let typeEncoded = encodeItemType(item.type)
            let dispositionEncoded = encodeDisposition(item.disposition)
            let scopeEncoded = encodeScope(item.scope)
            try db.execute(sql: """
                INSERT INTO btm_items
                (snapshot_id, identifier, name, developer_name, bundle_identifier,
                 team_identifier, type_kind, type_raw, disposition_kind, disposition_raw,
                 scope_kind, scope_per_user_uuid, modification_date, parent_identifier)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    snapshotID,
                    item.identifier,
                    item.name,
                    item.developerName,
                    item.bundleIdentifier,
                    item.teamIdentifier,
                    typeEncoded.kind,
                    typeEncoded.raw,
                    dispositionEncoded.kind,
                    item.dispositionRaw,
                    scopeEncoded.kind,
                    scopeEncoded.uuid,
                    item.modificationDate,
                    item.parentIdentifier,
                ])
        }
    }

    // MARK: - Private read helpers

    private static func launchAgentFromRow(_ row: Row) throws -> LaunchAgentItem {
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
            keepAlive: row["keep_alive"],
            isDisabled: row["is_disabled"]
        )
    }

    private static func tccGrantFromRow(_ row: Row) throws -> PermissionGrant {
        let serviceRaw: String = row["service"]
        guard let service = PermissionService(rawValue: serviceRaw) else {
            throw StoreError.unknownPermissionService(serviceRaw)
        }
        let bundleID: String = row["bundle_id"]
        let displayName: String = row["display_name"]
        let bundlePathString: String? = row["bundle_path"]
        let bundlePath = bundlePathString.map { URL(fileURLWithPath: $0) }
        let lastModified: Date = row["last_modified"]
        let automationTarget: String? = row["automation_target"]
        let authValue: Int = row["auth_value"] ?? 2
        return PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: displayName, bundlePath: bundlePath),
            lastModified: lastModified,
            automationTarget: automationTarget,
            authValue: authValue
        )
    }

    private static func btmItemFromRow(_ row: Row) throws -> BTMItem {
        let identifier: String = row["identifier"]
        let name: String = row["name"]
        let typeKind: String = row["type_kind"]
        let typeRaw: Int? = row["type_raw"]
        let dispositionKind: String = row["disposition_kind"]
        let dispositionRawDB: Int? = row["disposition_raw"]
        let dispositionRaw: Int = dispositionRawDB ?? 0
        let scopeKind: String = row["scope_kind"]
        let scopeUUID: String? = row["scope_per_user_uuid"]
        let modificationDate: Date = row["modification_date"]
        return BTMItem(
            identifier: identifier,
            name: name,
            developerName: row["developer_name"],
            bundleIdentifier: row["bundle_identifier"],
            teamIdentifier: row["team_identifier"],
            type: try decodeItemType(kind: typeKind, raw: typeRaw),
            disposition: try decodeDisposition(kind: dispositionKind, raw: dispositionRawDB),
            dispositionRaw: dispositionRaw,
            scope: try decodeScope(kind: scopeKind, uuid: scopeUUID),
            modificationDate: modificationDate,
            parentIdentifier: row["parent_identifier"]
        )
    }

    // MARK: - JSON helpers (LaunchAgent programArguments)

    private static func encodeArguments(_ args: [String]) throws -> String {
        let data = try JSONEncoder().encode(args)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeArguments(_ json: String) throws -> [String] {
        let data = Data(json.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }

    // MARK: - BTM enum encoding

    private static func encodeItemType(_ type: BTMItem.ItemType) -> (kind: String, raw: Int?) {
        switch type {
        case .app:            ("app", nil)
        case .legacyDaemon:   ("legacyDaemon", nil)
        case .developerGroup: ("developerGroup", nil)
        case .unknown(let r): ("unknown", r)
        }
    }

    // internal (not private): the unknown-kind throw is a data-integrity guarantee
    // (a corrupt/foreign snapshot row surfaces as an error state, not silent
    // default). Exposed for BTMDecodeErrorTests. (R3)
    static func decodeItemType(kind: String, raw: Int?) throws -> BTMItem.ItemType {
        switch kind {
        case "app":            return .app
        case "legacyDaemon":   return .legacyDaemon
        case "developerGroup": return .developerGroup
        case "unknown":        return .unknown(rawValue: raw ?? 0)
        default:               throw StoreError.unknownBTMItemTypeKind(kind)
        }
    }

    private static func encodeDisposition(_ d: BTMItem.Disposition) -> (kind: String, raw: Int?) {
        switch d {
        case .enabled:        ("enabled", nil)
        case .disabled:       ("disabled", nil)
        case .unknown(let r): ("unknown", r)
        }
    }

    static func decodeDisposition(kind: String, raw: Int?) throws -> BTMItem.Disposition {
        switch kind {
        case "enabled":  return .enabled
        case "disabled": return .disabled
        case "unknown":  return .unknown(rawValue: raw ?? 0)
        default:         throw StoreError.unknownBTMDispositionKind(kind)
        }
    }

    private static func encodeScope(_ s: BTMItem.Scope) -> (kind: String, uuid: String?) {
        switch s {
        case .system:            ("system", nil)
        case .user:              ("user", nil)
        case .perUser(let uuid): ("perUser", uuid)
        }
    }

    static func decodeScope(kind: String, uuid: String?) throws -> BTMItem.Scope {
        switch kind {
        case "system":  return .system
        case "user":    return .user
        case "perUser":
            guard let uuid else { throw StoreError.missingPerUserScopeUUID }
            return .perUser(uuid: uuid)
        default:        throw StoreError.unknownBTMScopeKind(kind)
        }
    }
}

public enum StoreError: Error, Sendable {
    case unknownSourceDirectory(String)
    case unknownPermissionService(String)
    case unknownBTMItemTypeKind(String)
    case unknownBTMDispositionKind(String)
    case unknownBTMScopeKind(String)
    case missingPerUserScopeUUID
    case snapshotNotFound(Int64)
}
