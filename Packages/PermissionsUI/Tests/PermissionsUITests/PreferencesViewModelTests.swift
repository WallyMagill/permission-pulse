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

    @Test func sendTestNotificationFlowsThroughClosure() async {
        var callCount = 0
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onSendTestNotification: {
                callCount += 1
                return .scheduled(in: 5)
            }
        )
        await vm.sendTestNotification()
        #expect(callCount == 1)
        if case .scheduled(let seconds) = vm.testNotificationResult {
            #expect(seconds == 5)
        } else {
            Issue.record("Expected .scheduled(in: 5), got \(vm.testNotificationResult)")
        }
    }

    @Test func clearTestNotificationResultResetsToIdle() async {
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onSendTestNotification: { .notAuthorized }
        )
        await vm.sendTestNotification()
        #expect(vm.testNotificationResult == .notAuthorized)
        vm.clearTestNotificationResult()
        #expect(vm.testNotificationResult == .idle)
    }

    @Test func refreshAuthorizationHintAlsoFetchesNextFireDate() async {
        let target = Date(timeIntervalSince1970: 1_800_000_000)
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onDigestToggle: { _ in .scheduled(nextFireDescription: "") },
            onFetchNextFireDate: { target }
        )
        await vm.refreshAuthorizationHint()
        #expect(vm.nextWeeklyFireDate == target)
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "prefs-vm-test-\(UUID().uuidString)")!
    }
}
