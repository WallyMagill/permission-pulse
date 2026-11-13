import Testing
@testable import PermissionsUI

@Suite("Stale Apps empty state")
struct StaleAppsEmptyStateTests {
    @Test("No permission data is not reported as every app being recently used")
    func noPermissionData() {
        let state = StaleAppsEmptyState.resolve(hasPermissionData: false, historyAvailable: true, systemLevelOnly: false)
        #expect(state == .noPermissionData)
        #expect(!state.description.contains("used recently"))
    }

    @Test("Missing history is its own empty state")
    func historyUnavailable() {
        let state = StaleAppsEmptyState.resolve(hasPermissionData: true, historyAvailable: false, systemLevelOnly: false)
        #expect(state == .historyUnavailable)
        #expect(!state.description.contains("used recently"))
    }

    @Test("With data and history, the all-used copy matches the scope")
    func noneStale() {
        let full = StaleAppsEmptyState.resolve(hasPermissionData: true, historyAvailable: true, systemLevelOnly: false)
        #expect(full.description == "Every app with an active grant has been used recently.")
        let reduced = StaleAppsEmptyState.resolve(hasPermissionData: true, historyAvailable: true, systemLevelOnly: true)
        #expect(reduced.description == "Every app with a system-level permission has been used recently.")
    }
}
