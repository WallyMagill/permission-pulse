import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct PermissionsScannersSmokeTests {
    @Test func mockTCCScannerReturnsGrants() async throws {
        let warning = ScannerWarning(source: .userTCCDatabase)
        let scanner = MockTCCScanner(warnings: [warning])
        let output = try await scanner.scan()
        #expect(!output.items.isEmpty)
        #expect(output.items.contains { $0.service == .screenRecording })
        #expect(output.warnings == [warning])
    }

    @Test func mockLaunchAgentScannerReturnsItems() async throws {
        let warning = ScannerWarning(source: .entries, omittedCount: 1)
        let scanner = MockLaunchAgentScanner(warnings: [warning])
        let output = try await scanner.scan()
        #expect(!output.items.isEmpty)
        #expect(output.items.allSatisfy { !$0.label.isEmpty })
        #expect(output.warnings == [warning])
    }
}
