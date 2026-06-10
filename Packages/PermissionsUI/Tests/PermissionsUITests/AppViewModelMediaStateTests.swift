import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelMediaStateTests {
    @Test func micInUseDefaultsToFalse() {
        let vm = AppViewModel()
        #expect(vm.micInUse == false)
    }

    @Test func cameraInUseDefaultsToFalse() {
        let vm = AppViewModel()
        #expect(vm.cameraInUse == false)
    }

    @Test func mediaDataSourceDefaultsToMock() {
        let vm = AppViewModel()
        #expect(vm.mediaDataSource == .mock)
    }

    @Test func micInUseAssignmentPropagatesToSymbol() {
        let vm = AppViewModel()
        vm.micInUse = true
        #expect(vm.menuBarSymbolName == "mic.fill")
    }

    @Test func cameraInUseAssignmentPropagatesToSymbol() {
        let vm = AppViewModel()
        vm.cameraInUse = true
        #expect(vm.menuBarSymbolName == "video.fill")
    }

    @Test func clearingBothMediaFlagsReturnsToIdle() {
        let vm = AppViewModel(micInUse: true, cameraInUse: true)
        vm.micInUse = false
        vm.cameraInUse = false
        #expect(vm.menuBarSymbolName == "shield.lefthalf.filled")
    }
}
