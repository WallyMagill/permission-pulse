import Testing
import Foundation
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct PermissionsUISmokeTests {
    @Test func appViewModelInitializesEmpty() {
        let vm = AppViewModel()
        #expect(vm.grants.isEmpty)
        #expect(vm.launchAgents.isEmpty)
        #expect(vm.dataSource == .mock)
    }

    @Test func appViewModelAcceptsMockData() {
        let grants = [
            PermissionGrant(
                service: .accessibility,
                app: AppIdentity(bundleID: "com.example.test", displayName: "Test"),
                lastModified: Date()
            )
        ]
        let vm = AppViewModel(grants: grants, dataSource: .mock)
        #expect(vm.grants.count == 1)
        #expect(vm.dataSource == .mock)
    }
}
