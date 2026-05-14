import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelBTMStateTests {
    @Test func btmScanErrorDefaultsToNil() {
        let vm = AppViewModel()
        #expect(vm.btmScanError == nil)
    }

    @Test func btmScanErrorCanBeAssignedAndRead() {
        let vm = AppViewModel()
        vm.btmScanError = .permissionDenied(reason: "FDA needed")
        guard case .permissionDenied(let reason) = vm.btmScanError else {
            Issue.record("Expected .permissionDenied")
            return
        }
        #expect(reason == "FDA needed")
    }

    @Test func btmScanErrorInitParameterIsHonored() {
        let vm = AppViewModel(btmScanError: .schemaMismatch(detail: "missing itemsByUserIdentifier"))
        guard case .schemaMismatch(let detail) = vm.btmScanError else {
            Issue.record("Expected .schemaMismatch")
            return
        }
        #expect(detail == "missing itemsByUserIdentifier")
    }

    @Test func btmScanErrorCanBeClearedToNil() {
        let vm = AppViewModel(btmScanError: .unsupportedOnThisOS(detail: "unknown BTM file version"))
        vm.btmScanError = nil
        #expect(vm.btmScanError == nil)
    }

    @Test func btmDataSourceDefaultsToMock() {
        let vm = AppViewModel()
        #expect(vm.btmDataSource == .mock)
    }

    @Test func btmItemsDefaultsToEmpty() {
        let vm = AppViewModel()
        #expect(vm.btmItems.isEmpty)
    }
}
