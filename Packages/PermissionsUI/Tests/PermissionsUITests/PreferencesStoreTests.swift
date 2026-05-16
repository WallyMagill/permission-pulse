import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct PreferencesStoreTests {
    @Test func defaultsAreReadWhenNothingPersisted() {
        let store = PreferencesStore(defaults: fresh())
        #expect(store.snapshotRetentionDays == 90)
        #expect(store.staleThresholdDays == 90)
        #expect(store.digestEnabled == false)
        #expect(store.digestWeekday == 2)
        #expect(store.digestHour == 9)
        #expect(store.digestMinute == 0)
    }

    @Test func persistsAndReloadsRetentionDays() {
        let defaults = fresh()
        let writer = PreferencesStore(defaults: defaults)
        writer.snapshotRetentionDays = 120
        let reader = PreferencesStore(defaults: defaults)
        #expect(reader.snapshotRetentionDays == 120)
    }

    @Test func persistsAndReloadsStaleThresholdDays() {
        let defaults = fresh()
        let writer = PreferencesStore(defaults: defaults)
        writer.staleThresholdDays = 180
        let reader = PreferencesStore(defaults: defaults)
        #expect(reader.staleThresholdDays == 180)
    }

    @Test func clampsRetentionToValidRange() {
        let defaults = fresh()
        let store = PreferencesStore(defaults: defaults)
        store.snapshotRetentionDays = 0
        #expect(store.snapshotRetentionDays == 7)
        store.snapshotRetentionDays = 1000
        #expect(store.snapshotRetentionDays == 365)
    }

    @Test func clampsStaleThresholdToValidRange() {
        let defaults = fresh()
        let store = PreferencesStore(defaults: defaults)
        store.staleThresholdDays = 0
        #expect(store.staleThresholdDays == 30)
        store.staleThresholdDays = 1000
        #expect(store.staleThresholdDays == 365)
    }

    @Test func clampsWeekdayHourMinuteToValidRanges() {
        let store = PreferencesStore(defaults: fresh())
        store.digestWeekday = 0
        #expect(store.digestWeekday == 1)
        store.digestWeekday = 99
        #expect(store.digestWeekday == 7)
        store.digestHour = -1
        #expect(store.digestHour == 0)
        store.digestHour = 99
        #expect(store.digestHour == 23)
        store.digestMinute = -1
        #expect(store.digestMinute == 0)
        store.digestMinute = 99
        #expect(store.digestMinute == 59)
    }

    @Test func digestEnabledTogglesAndPersists() {
        let defaults = fresh()
        let writer = PreferencesStore(defaults: defaults)
        #expect(writer.digestEnabled == false)
        writer.digestEnabled = true
        let reader = PreferencesStore(defaults: defaults)
        #expect(reader.digestEnabled == true)
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "prefs-test-\(UUID().uuidString)")!
    }
}
