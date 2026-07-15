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

    @Test func zeroDebounceBurstInvokesScheduleChangeOnce() async {
        let store = PreferencesStore(defaults: fresh())
        store.digestEnabled = true
        var callCount = 0
        let vm = PreferencesViewModel(
            store: store,
            onDigestScheduleChange: {
                callCount += 1
                return .scheduled(nextFireDescription: "")
            },
            scheduleDebounce: .zero
        )

        vm.scheduleDidChange()
        vm.scheduleDidChange()
        vm.scheduleDidChange()
        await yieldUntil { callCount == 1 }
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(callCount == 1)
    }

    @Test func failedScheduleChangeClearsStaleNextFireAndSurfacesExactHint() async {
        let store = PreferencesStore(defaults: fresh())
        store.digestEnabled = true
        let staleDate = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = PreferencesViewModel(
            store: store,
            onDigestScheduleChange: { .failed("injected scheduling failure") },
            onFetchNextFireDate: { staleDate },
            scheduleDebounce: .zero
        )
        vm.nextWeeklyFireDate = staleDate

        vm.scheduleDidChange()
        await yieldUntil { vm.authorizationHint == .failed("injected scheduling failure") }

        #expect(vm.authorizationHint == .failed("injected scheduling failure"))
        #expect(vm.nextWeeklyFireDate == nil)
    }

    @Test func disablingDuringDebounceCannotReschedule() async {
        let store = PreferencesStore(defaults: fresh())
        store.digestEnabled = true
        var scheduleCallCount = 0
        let vm = PreferencesViewModel(
            store: store,
            onDigestToggle: { _ in .disabled },
            onDigestScheduleChange: {
                scheduleCallCount += 1
                return .scheduled(nextFireDescription: "")
            },
            scheduleDebounce: .seconds(60)
        )

        vm.scheduleDidChange()
        await vm.handleDigestToggle(to: false)
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(scheduleCallCount == 0)
        #expect(vm.authorizationHint == .disabled)
        #expect(vm.nextWeeklyFireDate == nil)
    }

    @Test func retryClearsScheduleFailureAndRefreshesNextFire() async {
        let store = PreferencesStore(defaults: fresh())
        store.digestEnabled = true
        let target = Date(timeIntervalSince1970: 1_800_000_000)
        var callCount = 0
        let vm = PreferencesViewModel(
            store: store,
            onDigestScheduleChange: {
                callCount += 1
                return callCount == 1
                    ? .failed("injected scheduling failure")
                    : .scheduled(nextFireDescription: "")
            },
            onFetchNextFireDate: { target },
            scheduleDebounce: .zero
        )

        vm.scheduleDidChange()
        await yieldUntil { vm.authorizationHint == .failed("injected scheduling failure") }
        vm.scheduleDidChange()
        await yieldUntil { callCount == 2 && vm.nextWeeklyFireDate == target }

        #expect(vm.authorizationHint == .scheduled(nextFireDescription: ""))
        #expect(vm.nextWeeklyFireDate == target)
    }

    @Test func deinitializingDuringDebounceCancelsPendingScheduleChange() async {
        let store = PreferencesStore(defaults: fresh())
        store.digestEnabled = true
        var callCount = 0
        var vm: PreferencesViewModel? = PreferencesViewModel(
            store: store,
            onDigestScheduleChange: {
                callCount += 1
                return .scheduled(nextFireDescription: "")
            },
            scheduleDebounce: .seconds(60)
        )
        weak let weakViewModel = vm

        vm?.scheduleDidChange()
        vm = nil
        for _ in 0 ..< 10 { await Task.yield() }

        #expect(weakViewModel == nil)
        #expect(callCount == 0)
    }

    @Test("Launch-at-login toggle applies the system result, not the request")
    @MainActor
    func launchAtLoginAppliesSystemResult() async {
        var requested: Bool?
        let vm = PreferencesViewModel(
            store: PreferencesStore(defaults: fresh()),
            onDigestToggle: { _ in .disabled },
            onSendTestNotification: { .idle },
            onFetchNextFireDate: { nil },
            initialLaunchAtLogin: false,
            onLaunchAtLoginToggle: { enable in
                requested = enable
                return false   // system refused (e.g. SMAppService error)
            }
        )
        await vm.setLaunchAtLogin(true)
        #expect(requested == true)
        #expect(vm.launchAtLoginEnabled == false)  // reflects reality, not the wish
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "prefs-vm-test-\(UUID().uuidString)")!
    }

    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 1_000 {
            if condition() { return }
            await Task.yield()
        }
    }
}
