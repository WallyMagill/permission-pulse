import Foundation
import Testing
import GRDB
import PermissionsCore
@testable import PermissionsScanners

@Suite struct ScannerErrorMappingTests {
    @Test func cantOpenMapsToPermissionDenied() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_CANTOPEN))
        guard case .permissionDenied = mapped else {
            Issue.record("Expected .permissionDenied, got \(mapped)"); return
        }
    }

    @Test func corruptMapsToSchemaMismatch() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_CORRUPT))
        guard case .schemaMismatch = mapped else {
            Issue.record("Expected .schemaMismatch, got \(mapped)"); return
        }
    }

    @Test func busyMapsToTemporarilyUnavailable() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_BUSY))
        guard case .temporarilyUnavailable(let reason) = mapped else {
            Issue.record("Expected .temporarilyUnavailable, got \(mapped)"); return
        }
        #expect(reason.contains("Refresh"))
    }

    @Test func ioErrorMapsToTemporarilyUnavailable() {
        let mapped = TCCScannerSQLite.mapDatabaseError(DatabaseError(resultCode: .SQLITE_IOERR))
        guard case .temporarilyUnavailable(let reason) = mapped else {
            Issue.record("Expected .temporarilyUnavailable, got \(mapped)"); return
        }
        #expect(reason.contains("disk"))
    }

    @Test func unrecognizedDatabaseErrorMapsToTemporarilyUnavailable() {
        let mapped = TCCScannerSQLite.mapDatabaseError(
            DatabaseError(resultCode: .SQLITE_CONSTRAINT, message: "injected constraint")
        )
        guard case .temporarilyUnavailable(let reason) = mapped else {
            Issue.record("Expected .temporarilyUnavailable, got \(mapped)"); return
        }
        #expect(reason.contains("Refresh"))
    }

    @Test func nonDatabaseReadErrorMapsToTemporarilyUnavailable() {
        let mapped = TCCScannerSQLite.mapReadError(InjectedReadError())
        guard case .temporarilyUnavailable(let reason) = mapped else {
            Issue.record("Expected .temporarilyUnavailable, got \(mapped)"); return
        }
        #expect(reason.contains("Refresh"))
    }
}

private struct InjectedReadError: LocalizedError {
    var errorDescription: String? { "injected non-database failure" }
}
