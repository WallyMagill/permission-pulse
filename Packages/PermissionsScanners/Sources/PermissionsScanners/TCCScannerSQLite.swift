import AppKit
import Foundation
import GRDB
import OSLog
import PermissionsCore

public protocol ApplicationResolving: Sendable {
    func applicationURL(forBundleIdentifier bundleID: String) async -> URL?
}

public struct WorkspaceApplicationResolver: ApplicationResolving {
    public init() {}

    public func applicationURL(forBundleIdentifier bundleID: String) async -> URL? {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
    }
}

public struct TCCScannerSQLite: TCCScanner, Sendable {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "scanners.tcc"
    )

    private static let requiredColumns: Set<String> = [
        "service", "client", "client_type", "auth_value", "last_modified",
    ]

    private static var userDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
    }

    private static let systemDatabaseURL = URL(
        fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"
    )

    private let databaseURLs: [URL]
    private let applicationResolver: any ApplicationResolving

    public init() {
        self.databaseURLs = [Self.userDatabaseURL, Self.systemDatabaseURL]
        self.applicationResolver = WorkspaceApplicationResolver()
    }

    public init(
        databaseURLs: [URL],
        applicationResolver: any ApplicationResolving = WorkspaceApplicationResolver()
    ) {
        self.databaseURLs = databaseURLs
        self.applicationResolver = applicationResolver
    }

    public func scan() async throws -> ScannerOutput<PermissionGrant> {
        let results = await readAllDatabases()

        let failures = results.compactMap { index, url, result -> (Int, URL, any Error)? in
            switch result {
            case .success: return nil
            case .failure(let error): return (index, url, error)
            }
        }

        let successes = results.compactMap { _, _, result -> [TCCRow]? in
            try? result.get()
        }

        if successes.isEmpty, let firstFailure = failures.first {
            throw firstFailure.2
        }

        for (_, url, error) in failures {
            Self.logger.error("TCC read failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        let rows = successes.flatMap { $0 }
        let resolvedURLs = await resolveApplicationURLs(for: rows)
        let combined = rows.compactMap {
            Self.mapRowToGrant($0, resolvedURLs: resolvedURLs)
        }
        let items = Self.dedupe(combined).sorted(by: Self.sortGrants)
        let warnings = failures.map { index, _, _ in
            ScannerWarning(source: Self.scannerSource(forDatabaseAt: index))
        }
        return ScannerOutput(items: items, warnings: warnings)
    }

    // TCC.db produces duplicates in two common situations:
    //   1. The same (service, app, automationTarget) tuple appears in both
    //      the user TCC and system TCC databases.
    //   2. PermissionService.filesAndFolders maps from FIVE distinct TCC
    //      strings (Desktop, Documents, Downloads, NetworkVolumes,
    //      RemovableVolumes), so an app granted access to multiple folders
    //      emits multiple PermissionGrant rows that look identical in the
    //      UI (same service, same app, no automation target).
    //
    // Dedupe by (service, app-key, automationTarget). When duplicates
    // collide, keep the entry with the most recent lastModified — that is
    // the most useful timestamp for "when did the user last touch this."
    //
    // Future v0.7.0+ work could preserve the specific folder grants for
    // .filesAndFolders by adding a sub-service tag to PermissionGrant.
    private static func dedupe(_ grants: [PermissionGrant]) -> [PermissionGrant] {
        var byKey: [String: PermissionGrant] = [:]
        for grant in grants {
            let appKey = grant.app.stableKey ?? grant.appKey
            let key = "\(grant.service.rawValue)|\(appKey)|\(grant.automationTarget ?? "")"
            if let existing = byKey[key], existing.lastModified >= grant.lastModified {
                continue
            }
            byKey[key] = grant
        }
        return Array(byKey.values)
    }

    private func readAllDatabases() async -> [(Int, URL, Result<[TCCRow], any Error>)] {
        await withTaskGroup(
            of: (Int, URL, Result<[TCCRow], any Error>).self
        ) { group in
            for (index, url) in databaseURLs.enumerated() {
                group.addTask {
                    do {
                        let rows = try await Self.readRows(from: url)
                        return (index, url, .success(rows))
                    } catch {
                        return (index, url, .failure(error))
                    }
                }
            }
            var collected: [(Int, URL, Result<[TCCRow], any Error>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected.sorted { $0.0 < $1.0 }
        }
    }

    private static func scannerSource(forDatabaseAt index: Int) -> ScannerSource {
        switch index {
        case 0: .userTCCDatabase
        case 1: .systemTCCDatabase
        default: .entries
        }
    }

    private static func readRows(from url: URL) async throws -> [TCCRow] {
        var config = Configuration()
        config.readonly = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only = 1")
        }

        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(
                path: url.path(percentEncoded: false),
                configuration: config
            )
        } catch let dbError as DatabaseError {
            throw mapDatabaseError(dbError)
        } catch {
            throw ScannerError.permissionDenied(reason: permissionDeniedReason)
        }

        do {
            return try await queue.read { db in
                try validateSchema(db)
                return try fetchRows(from: db)
            }
        } catch let scannerError as ScannerError {
            throw scannerError
        } catch let dbError as DatabaseError {
            throw mapDatabaseError(dbError)
        } catch {
            throw ScannerError.permissionDenied(reason: permissionDeniedReason)
        }
    }

    private static func validateSchema(_ db: Database) throws {
        let columns = try String.fetchAll(
            db,
            sql: "SELECT name FROM pragma_table_info('access')"
        )
        if columns.isEmpty {
            throw ScannerError.unsupportedOnThisOS(
                detail: String(localized: "TCC access table not found.")
            )
        }
        let missing = requiredColumns.subtracting(Set(columns))
        if !missing.isEmpty {
            let sortedMissing = missing.sorted().joined(separator: ", ")
            throw ScannerError.schemaMismatch(
                detail: String(
                    localized: "TCC.db schema mismatch: missing columns [\(sortedMissing)]. macOS may have changed the schema."
                )
            )
        }
    }

    private static func fetchRows(from db: Database) throws -> [TCCRow] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT service, client, client_type, auth_value, last_modified, indirect_object_identifier
            FROM access
            """)
        return rows.compactMap(TCCRow.init(row:))
    }

    private func resolveApplicationURLs(for rows: [TCCRow]) async -> [String: URL] {
        let bundleIDs = Set(rows.compactMap { row -> String? in
            guard row.clientType == 0,
                  let client = row.client,
                  !client.isEmpty else { return nil }
            return client
        })

        var resolvedURLs: [String: URL] = [:]
        for bundleID in bundleIDs.sorted() {
            if let url = await applicationResolver.applicationURL(
                forBundleIdentifier: bundleID
            ) {
                resolvedURLs[bundleID] = url
            }
        }
        return resolvedURLs
    }

    private static func mapRowToGrant(
        _ row: TCCRow,
        resolvedURLs: [String: URL]
    ) -> PermissionGrant? {
        // Keep allowed (2), limited (3), and any future affirmative value; drop
        // denied (0) and undetermined (1). (D2)
        guard row.authValue >= 2 else { return nil }

        guard let service = PermissionService(tccServiceString: row.service) else {
            if PermissionService.knownSkipped.contains(row.service) {
                logger.debug("Skip known-skipped service \(row.service, privacy: .public) for client \(row.client ?? "<unknown>", privacy: .public)")
            } else {
                logger.debug("Skip unknown service \(row.service, privacy: .public) for client \(row.client ?? "<unknown>", privacy: .public)")
            }
            return nil
        }

        guard let identity = buildAppIdentity(
            client: row.client,
            clientType: row.clientType,
            resolvedURLs: resolvedURLs
        ) else {
            return nil
        }

        let automationTarget: String? = (service == .automation && row.indirectObjectIdentifier != "UNUSED")
            ? row.indirectObjectIdentifier
            : nil
        let lastModified = Date(timeIntervalSince1970: TimeInterval(row.lastModified))
        return PermissionGrant(
            service: service,
            app: identity,
            lastModified: lastModified,
            automationTarget: automationTarget,
            authValue: row.authValue
        )
    }

    private static func buildAppIdentity(
        client: String?,
        clientType: Int?,
        resolvedURLs: [String: URL]
    ) -> AppIdentity? {
        guard let client, !client.isEmpty, let clientType else { return nil }
        switch clientType {
        case 0:
            let url = resolvedURLs[client]
            let resolvedName = url.map {
                FileManager.default.displayName(atPath: $0.path(percentEncoded: false))
            }
            let displayName = resolvedName.flatMap { $0.isEmpty ? nil : $0 } ?? client
            return AppIdentity(
                bundleID: client,
                displayName: displayName,
                bundlePath: url
            )
        case 1:
            let url = URL(fileURLWithPath: client).standardizedFileURL
            let name = url.deletingPathExtension().lastPathComponent
            return AppIdentity(bundleID: "", displayName: name, bundlePath: url)
        default:
            return nil
        }
    }

    private static func sortGrants(_ a: PermissionGrant, _ b: PermissionGrant) -> Bool {
        if a.service.rawValue != b.service.rawValue {
            return a.service.rawValue < b.service.rawValue
        }
        let aKey = a.app.stableKey ?? a.appKey
        let bKey = b.app.stableKey ?? b.appKey
        if aKey != bKey {
            return aKey < bKey
        }
        return a.lastModified < b.lastModified
    }

    // internal (not private): exposed for unit testing via @testable import.
    static func mapDatabaseError(_ error: DatabaseError) -> ScannerError {
        // FDA-missing surfaces as CANTOPEN/AUTH/PERM/READONLY and is the
        // dominant cause; corruption and transient locks need different advice
        // so we don't send users on a Full-Disk-Access wild goose chase. (C5)
        switch error.resultCode.primaryResultCode {
        case .SQLITE_CANTOPEN, .SQLITE_AUTH, .SQLITE_PERM, .SQLITE_READONLY:
            return .permissionDenied(reason: permissionDeniedReason)
        case .SQLITE_CORRUPT, .SQLITE_NOTADB:
            return .schemaMismatch(detail: corruptReason)
        case .SQLITE_BUSY, .SQLITE_LOCKED:
            return .temporarilyUnavailable(reason: busyReason)
        case .SQLITE_IOERR:
            return .temporarilyUnavailable(reason: ioErrorReason)
        default:
            return .permissionDenied(reason: permissionDeniedReason)
        }
    }

    private static let permissionDeniedReason = String(
        localized: "Full Disk Access is required. Grant it in System Settings → Privacy & Security → Full Disk Access."
    )

    private static let corruptReason = String(
        localized: "The TCC database appears to be unreadable or corrupt."
    )

    private static let busyReason = String(
        localized: "The TCC database is temporarily locked by macOS. Try Refresh in a moment."
    )

    private static let ioErrorReason = String(
        localized: "A disk I/O error occurred reading the TCC database. Check available disk space and try Refresh."
    )

    private struct TCCRow: Sendable {
        let service: String
        let client: String?
        let clientType: Int?
        let authValue: Int
        let lastModified: Int64
        let indirectObjectIdentifier: String

        init?(row: Row) {
            // TCC.db is foreign and untrusted, and SQLite type affinity is
            // advisory — a cell can hold any storage class. GRDB's typed
            // subscripts trap (`try!`) on unconvertible values, so decode via
            // the non-throwing raw subscript and drop or default anomalous
            // cells instead: under-flag, never crash.
            guard let service = Self.text(row, "service") else { return nil }
            self.service = service
            self.client = Self.text(row, "client")
            self.clientType = Self.integer(row, "client_type").map(Int.init)
            self.authValue = Self.integer(row, "auth_value").map(Int.init) ?? -1
            self.lastModified = Self.integer(row, "last_modified") ?? 0
            self.indirectObjectIdentifier = Self.text(row, "indirect_object_identifier") ?? "UNUSED"
        }

        private static func text(_ row: Row, _ column: String) -> String? {
            let value: (any DatabaseValueConvertible)? = row[column]
            return value as? String
        }

        private static func integer(_ row: Row, _ column: String) -> Int64? {
            let value: (any DatabaseValueConvertible)? = row[column]
            return value as? Int64
        }
    }
}
