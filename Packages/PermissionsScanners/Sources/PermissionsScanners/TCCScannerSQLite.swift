import Foundation
import GRDB
import OSLog
import PermissionsCore

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

    public init() {
        self.databaseURLs = [Self.userDatabaseURL, Self.systemDatabaseURL]
    }

    init(databaseURLs: [URL]) {
        self.databaseURLs = databaseURLs
    }

    public func scan() async throws -> [PermissionGrant] {
        let results = await readAllDatabases()

        let failures = results.compactMap { url, result -> (URL, any Error)? in
            switch result {
            case .success: return nil
            case .failure(let error): return (url, error)
            }
        }

        let successes = results.compactMap { _, result -> [PermissionGrant]? in
            try? result.get()
        }

        if successes.isEmpty, let firstFailure = failures.first {
            throw firstFailure.1
        }

        for (url, error) in failures {
            Self.logger.error("TCC read failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        return successes.flatMap { $0 }.sorted(by: Self.sortGrants)
    }

    private func readAllDatabases() async -> [(URL, Result<[PermissionGrant], any Error>)] {
        await withTaskGroup(
            of: (URL, Result<[PermissionGrant], any Error>).self
        ) { group in
            for url in databaseURLs {
                group.addTask {
                    do {
                        let grants = try await Self.readGrants(from: url)
                        return (url, .success(grants))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            var collected: [(URL, Result<[PermissionGrant], any Error>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }
    }

    private static func readGrants(from url: URL) async throws -> [PermissionGrant] {
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
                let rows = try fetchRows(from: db)
                return rows.compactMap(mapRowToGrant)
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

    private static func mapRowToGrant(_ row: TCCRow) -> PermissionGrant? {
        guard row.authValue == 2 else { return nil }

        guard let service = PermissionService(tccServiceString: row.service) else {
            if PermissionService.knownSkipped.contains(row.service) {
                logger.debug("Skip known-skipped service \(row.service, privacy: .public) for client \(row.client ?? "<unknown>", privacy: .public)")
            } else {
                logger.debug("Skip unknown service \(row.service, privacy: .public) for client \(row.client ?? "<unknown>", privacy: .public)")
            }
            return nil
        }

        guard let identity = buildAppIdentity(client: row.client, clientType: row.clientType) else {
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
            automationTarget: automationTarget
        )
    }

    private static func buildAppIdentity(client: String?, clientType: Int?) -> AppIdentity? {
        guard let client, !client.isEmpty, let clientType else { return nil }
        switch clientType {
        case 0:
            return AppIdentity(bundleID: client, displayName: client)
        case 1:
            let url = URL(fileURLWithPath: client)
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
        if a.app.bundleID != b.app.bundleID {
            return a.app.bundleID < b.app.bundleID
        }
        return a.lastModified < b.lastModified
    }

    private static func mapDatabaseError(_ error: DatabaseError) -> ScannerError {
        // For v0.3.0, every SQLite open/read error funnels to permissionDenied.
        // FDA missing is the dominant cause; v0.3.1 will refine.
        ScannerError.permissionDenied(reason: permissionDeniedReason)
    }

    private static let permissionDeniedReason = String(
        localized: "Full Disk Access is required. Grant it in System Settings → Privacy & Security → Full Disk Access."
    )

    private struct TCCRow: Sendable {
        let service: String
        let client: String?
        let clientType: Int?
        let authValue: Int
        let lastModified: Int64
        let indirectObjectIdentifier: String

        init?(row: Row) {
            guard let service: String = row["service"] else { return nil }
            self.service = service
            self.client = row["client"]
            self.clientType = row["client_type"]
            self.authValue = row["auth_value"] ?? -1
            self.lastModified = row["last_modified"] ?? 0
            self.indirectObjectIdentifier = row["indirect_object_identifier"] ?? "UNUSED"
        }
    }
}
