import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct MockBTMScannerTests {
    @Test func scanReturnsThreeLabeledItems() async throws {
        let scanner = MockBTMScanner()
        let items = try await scanner.scan()

        #expect(items.count == 3)
        let types = items.map(\.type)
        #expect(types.contains(.app))
        #expect(types.contains(.legacyDaemon))
        let dispositions = Set(items.map(\.disposition))
        #expect(dispositions == [.enabled, .disabled])
    }
}
