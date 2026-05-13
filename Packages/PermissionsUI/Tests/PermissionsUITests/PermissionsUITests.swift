import Testing
import Foundation
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct PermissionsUISmokeTests {
    @Test func appViewModelInitializesEmpty() {
        let vm = AppViewModel()
        #expect(vm.grants.isEmpty)
        #expect(vm.launchAgents.isEmpty)
        #expect(vm.tccDataSource == .mock)
        #expect(vm.launchAgentsDataSource == .mock)
    }

    @Test func appViewModelAcceptsMockData() {
        let grants = [
            PermissionGrant(
                service: .accessibility,
                app: AppIdentity(bundleID: "com.example.test", displayName: "Test"),
                lastModified: Date()
            )
        ]
        let vm = AppViewModel(grants: grants, tccDataSource: .mock)
        #expect(vm.grants.count == 1)
        #expect(vm.tccDataSource == .mock)
        #expect(vm.launchAgentsDataSource == .mock)
    }

    @Test func appViewModelAcceptsMixedDataSources() {
        let vm = AppViewModel(
            tccDataSource: .mock,
            launchAgentsDataSource: .live
        )
        #expect(vm.tccDataSource == .mock)
        #expect(vm.launchAgentsDataSource == .live)
    }
}
