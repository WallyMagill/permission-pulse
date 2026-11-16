import Foundation
import GRDB
import PermissionsCore

extension SnapshotStore {
    // MARK: - Summaries

    /// Snapshots taken at or before `cutoff`, newest first.
    public func snapshotSummaries(atOrBefore cutoff: Date) async throws -> [SnapshotSummary] {
        try await dbQueue.read { db in
            try Self.fetchSummaries(db, atOrBefore: cutoff)
        }
    }

    public func snapshotSummary(id: SnapshotID) async throws -> SnapshotSummary? {
        try await dbQueue.read { db in
            try Self.fetchSummaries(db, sql: "\(Self.summarySelect) WHERE id = ?", arguments: [id.rawValue]).first
        }
    }

    // MARK: - Retention

    /// Deletes snapshots older than `cutoff`, except the overall latest, the
    /// newest one at or before the cutoff (snapshots are written only on
    /// change, so that row *is* the state at the cutoff), every snapshot a
    /// domain could still use as its baseline, and `protected`.
    @discardableResult
    public func pruneSnapshots(
        olderThan cutoff: Date,
        keeping protected: Set<SnapshotID> = []
    ) async throws -> Int {
        try await dbQueue.write { db in
            let candidates = try Self.fetchSummaries(db, atOrBefore: cutoff)
            let latest = try Self.fetchSummaries(
                db,
                sql: "\(Self.summarySelect) ORDER BY created_at DESC, id DESC LIMIT 1"
            )
            var kept = protected.union(BaselineSelector.retainedBaselines(among: candidates))
            for summary in latest + candidates.prefix(1) {
                kept.insert(summary.id)
            }
            guard !kept.isEmpty else { return 0 }
            let placeholders = databaseQuestionMarks(count: kept.count)
            try db.execute(
                sql: "DELETE FROM snapshots WHERE created_at < ? AND id NOT IN (\(placeholders))",
                arguments: [cutoff] + StatementArguments(kept.map(\.rawValue))
            )
            return db.changesCount
        }
    }

    // MARK: - Private

    static let summarySelect = """
        SELECT id, created_at, tcc_coverage, btm_coverage, launch_agent_coverage
        FROM snapshots
        """

    private static func fetchSummaries(_ db: Database, atOrBefore cutoff: Date) throws -> [SnapshotSummary] {
        try fetchSummaries(
            db,
            sql: "\(summarySelect) WHERE created_at <= ? ORDER BY created_at DESC, id DESC",
            arguments: [cutoff]
        )
    }

    static func fetchSummaries(
        _ db: Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> [SnapshotSummary] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            SnapshotSummary(
                id: SnapshotID(rawValue: row["id"]),
                date: row["created_at"],
                coverage: SnapshotDomainCoverage(
                    tcc: decodeCoverage(row["tcc_coverage"]),
                    btm: decodeCoverage(row["btm_coverage"]),
                    launchAgents: decodeCoverage(row["launch_agent_coverage"])
                )
            )
        }
    }
}
