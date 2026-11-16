import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite struct StaleAppDateLineTests {
    private func staleApp(_ source: StaleApp.DateSource) -> StaleApp {
        StaleApp(
            app: AppIdentity(bundleID: "com.example.old", displayName: "Old"),
            lastUsedDate: Date(timeIntervalSince1970: 1_700_000_000),
            dateSource: source,
            daysSinceUsed: 120,
            grantedServices: [.camera]
        )
    }

    @Test func modificationDateFallbackIsNotCalledALastUse() {
        #expect(StaleAppsTabView.dateLine(for: staleApp(.fileSystem)).hasPrefix("Last modified "))
        #expect(StaleAppsTabView.dateLine(for: staleApp(.spotlight)).hasPrefix("Last used "))
    }
}
