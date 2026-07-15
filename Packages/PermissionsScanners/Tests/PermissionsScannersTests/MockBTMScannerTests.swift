import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct MockBTMScannerTests {
    @Test func scanReturnsThreeLabeledItems() async throws {
        let warning = ScannerWarning(source: .entries, omittedCount: 3)
        let scanner = MockBTMScanner(warnings: [warning])
        let output = try await scanner.scan()
        let items = output.items

        #expect(items.count == 3)
        let types = items.map(\.type)
        #expect(types.contains(.app))
        #expect(types.contains(.legacyDaemon))
        let dispositions = Set(items.map(\.disposition))
        #expect(dispositions == [.enabled, .disabled])
        #expect(output.warnings == [warning])
    }
}
