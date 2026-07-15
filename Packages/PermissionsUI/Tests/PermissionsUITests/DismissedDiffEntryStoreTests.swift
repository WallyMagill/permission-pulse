import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct DismissedDiffEntryStoreTests {
    @Test func dismissForeverPersists() {
        let defaults = fresh()
        let writer = DismissedDiffEntryStore(defaults: defaults)
        writer.dismissForever(key: "tcc-granted|microphone|com.x")
        let now = Date()

        let reader = DismissedDiffEntryStore(defaults: defaults)
        #expect(reader.isDismissed(key: "tcc-granted|microphone|com.x", asOf: now))
        // Distant future means never expires.
        #expect(reader.isDismissed(
            key: "tcc-granted|microphone|com.x",
            asOf: now.addingTimeInterval(365 * 86_400)
        ))
    }

    @Test func snoozeExpiresOnDate() {
        let store = DismissedDiffEntryStore(defaults: fresh())
        let expiry = Date(timeIntervalSince1970: 1_000_000)
        store.snooze(key: "k", until: expiry)

        #expect(store.isDismissed(key: "k", asOf: expiry.addingTimeInterval(-1)))
        #expect(!store.isDismissed(key: "k", asOf: expiry))
        #expect(!store.isDismissed(key: "k", asOf: expiry.addingTimeInterval(1)))
    }

    @Test func pruneExpiredRemovesPastEntries() {
        let defaults = fresh()
        let store = DismissedDiffEntryStore(defaults: defaults)
        let past = Date(timeIntervalSince1970: 1_000)
        let future = Date(timeIntervalSince1970: 9_999_999_999)
        store.snooze(key: "past", until: past)
        store.snooze(key: "future", until: future)
        let now = Date()

        store.pruneExpired(asOf: now)

        #expect(store.allEntries()["past"] == nil)
        #expect(store.allEntries()["future"] == future)
    }

    @Test func jsonRoundTripPreservesMap() {
        let defaults = fresh()
        let writer = DismissedDiffEntryStore(defaults: defaults)
        let expiry = Date(timeIntervalSince1970: 1_700_000_000)
        writer.snooze(key: "a", until: expiry)
        writer.dismissForever(key: "b")

        let reader = DismissedDiffEntryStore(defaults: defaults)
        #expect(reader.allEntries()["a"] == expiry)
        #expect(reader.allEntries()["b"] == .distantFuture)
    }

    @Test func corruptDefaultsReadsAsEmptyAndNextWriteRecovers() {
        let defaults = fresh()
        defaults.set("not json".data(using: .utf8)!, forKey: DismissedDiffEntryStore.key)

        let store = DismissedDiffEntryStore(defaults: defaults)
        #expect(store.allEntries().isEmpty)

        store.dismissForever(key: "after-recovery")
        let reader = DismissedDiffEntryStore(defaults: defaults)
        #expect(reader.allEntries()["after-recovery"] == .distantFuture)
    }

    @Test func removeAllClearsInMemoryAndPersistedEntriesIdempotently() {
        let defaults = fresh()
        let store = DismissedDiffEntryStore(defaults: defaults)
        store.dismissForever(key: "change")

        store.removeAll()

        #expect(store.allEntries().isEmpty)
        #expect(DismissedDiffEntryStore(defaults: defaults).allEntries().isEmpty)

        store.removeAll()

        #expect(store.allEntries().isEmpty)
        #expect(DismissedDiffEntryStore(defaults: defaults).allEntries().isEmpty)
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "dismiss-diff-test-\(UUID().uuidString)")!
    }
}
