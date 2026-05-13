import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct PermissionsScannersSmokeTests {
    @Test func mockTCCScannerReturnsGrants() async throws {
        let scanner = MockTCCScanner()
        let grants = try await scanner.scan()
        #expect(!grants.isEmpty)
        #expect(grants.contains { $0.service == .screenRecording })
    }

    @Test func mockLaunchAgentScannerReturnsItems() async throws {
        let scanner = MockLaunchAgentScanner()
        let items = try await scanner.scan()
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { !$0.label.isEmpty })
    }
}
