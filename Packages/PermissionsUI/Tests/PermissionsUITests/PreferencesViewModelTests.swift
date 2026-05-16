import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct PreferencesViewModelTests {
    @Test func sliderBindingRoundTripsRetentionThroughStore() {
        let defaults = fresh()
        let store = PreferencesStore(defaults: defaults)
        let vm = PreferencesViewModel(store: store)

        vm.snapshotRetentionDaysDouble = 120
        #expect(vm.snapshotRetentionDaysDouble == 120)

        let reload = PreferencesStore(defaults: defaults)
        #expect(reload.snapshotRetentionDays == 120)
    }

    @Test func digestToggleOffDoesNotInvokeScheduler() async {
        var callCount = 0
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onDigestToggle: { _ in
                callCount += 1
                return .disabled
            }
        )
        // Setting digestEnabled directly does NOT trigger the toggle handler
        // (that's only fired via handleDigestToggle, which the UI calls).
        vm.digestEnabled = false
        #expect(callCount == 0)
    }

    @Test func digestToggleOnSurfacesScheduledHint() async {
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onDigestToggle: { _ in .scheduled(nextFireDescription: "") }
        )
        await vm.handleDigestToggle(to: true)
        if case .scheduled = vm.authorizationHint {
            #expect(true)
        } else {
            Issue.record("Expected .scheduled hint, got \(vm.authorizationHint)")
        }
    }

    @Test func digestToggleOnSurfacesDeniedHintWhenDeniedByOS() async {
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onDigestToggle: { _ in .denied }
        )
        await vm.handleDigestToggle(to: true)
        #expect(vm.authorizationHint == .denied)
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "prefs-vm-test-\(UUID().uuidString)")!
    }
}
