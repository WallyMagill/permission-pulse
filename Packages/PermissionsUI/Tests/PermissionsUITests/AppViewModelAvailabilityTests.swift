import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelAvailabilityTests {
    @Test func availabilityFlagsDefaultFalse() {
        let vm = AppViewModel()
        #expect(vm.snapshotStoreUnavailable == false)
        #expect(vm.diffUnavailable == false)
    }

    @Test func availabilityFlagsAreSettable() {
        let vm = AppViewModel()
        vm.snapshotStoreUnavailable = true
        vm.diffUnavailable = true
        #expect(vm.snapshotStoreUnavailable)
        #expect(vm.diffUnavailable)
    }
}
