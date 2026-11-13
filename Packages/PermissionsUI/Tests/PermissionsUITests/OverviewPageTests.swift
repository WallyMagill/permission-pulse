import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("Overview") @MainActor
struct OverviewPageTests {
    @Test("A domain that never scanned successfully shows a dash, not zero")
    func unreadableCount() {
        let failed = OverviewPage.countDisplay(
            0,
            availability: .failed(lastSuccessful: nil, error: .permissionDenied(reason: "FDA"))
        )
        #expect(failed.value == "—")
        #expect(failed.note == "Not readable")

        let stale = OverviewPage.countDisplay(
            4,
            availability: .failed(lastSuccessful: Date(timeIntervalSince1970: 0), error: .permissionDenied(reason: "FDA"))
        )
        #expect(stale.value == "4")
        #expect(stale.note == nil)
    }

    @Test("Permission coverage names the reduced macOS 27 scope")
    func coverageText() {
        #expect(PermissionScope.systemLevelOnly.coverageText(hasData: true) == "System-level only (macOS 27)")
        #expect(PermissionScope.full.coverageText(hasData: true) == "All permissions")
        #expect(PermissionScope.full.coverageText(hasData: false) == "Unknown")
    }

    @Test("Each attention domain gets an Overview title naming it")
    func attentionTitlesNameTheDomain() {
        let title = OverviewPage.attentionTitle(.staleData([.backgroundItems]), domain: .backgroundItems)
        #expect(title.hasPrefix("Background Items"))
    }
}
