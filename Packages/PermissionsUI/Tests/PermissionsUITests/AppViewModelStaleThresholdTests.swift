import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelStaleThresholdTests {
    @Test func staleThresholdDaysDefaultsTo90() {
        #expect(AppViewModel().staleThresholdDays == 90)
    }

    @Test func staleThresholdDaysIsSettable() {
        let vm = AppViewModel()
        vm.staleThresholdDays = 30
        #expect(vm.staleThresholdDays == 30)
    }

    @Test func staleThresholdDaysInitParameterIsHonored() {
        let vm = AppViewModel(staleThresholdDays: 45)
        #expect(vm.staleThresholdDays == 45)
    }
}
