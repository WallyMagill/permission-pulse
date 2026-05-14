import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelErrorStateTests {
    @Test func tccScanErrorDefaultsToNil() {
        let vm = AppViewModel()
        #expect(vm.tccScanError == nil)
    }

    @Test func tccScanErrorCanBeAssignedAndRead() {
        let vm = AppViewModel()
        vm.tccScanError = .permissionDenied(reason: "FDA needed")
        guard case .permissionDenied(let reason) = vm.tccScanError else {
            Issue.record("Expected .permissionDenied")
            return
        }
        #expect(reason == "FDA needed")
    }

    @Test func tccScanErrorInitParameterIsHonored() {
        let vm = AppViewModel(tccScanError: .schemaMismatch(detail: "missing column foo"))
        guard case .schemaMismatch(let detail) = vm.tccScanError else {
            Issue.record("Expected .schemaMismatch")
            return
        }
        #expect(detail == "missing column foo")
    }

    @Test func tccScanErrorCanBeClearedToNil() {
        let vm = AppViewModel(tccScanError: .unsupportedOnThisOS(detail: "no access table"))
        vm.tccScanError = nil
        #expect(vm.tccScanError == nil)
    }
}
