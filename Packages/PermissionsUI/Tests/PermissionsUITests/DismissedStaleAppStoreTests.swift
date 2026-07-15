import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct DismissedStaleAppStoreTests {
    @Test func skipForeverPersistsAcrossInits() {
        let defaults = fresh()
        let writer = DismissedStaleAppStore(defaults: defaults)
        writer.skipForever(bundleID: "com.example.app")

        let reader = DismissedStaleAppStore(defaults: defaults)
        #expect(reader.contains(bundleID: "com.example.app"))
    }

    @Test func unskipRemovesBundleID() {
        let defaults = fresh()
        let store = DismissedStaleAppStore(defaults: defaults)
        store.skipForever(bundleID: "a")
        store.skipForever(bundleID: "b")

        store.unskip(bundleID: "a")

        let reader = DismissedStaleAppStore(defaults: defaults)
        #expect(!reader.contains(bundleID: "a"))
        #expect(reader.contains(bundleID: "b"))
    }

    @Test func corruptDefaultsReadsAsEmpty() {
        let defaults = fresh()
        defaults.set(42, forKey: DismissedStaleAppStore.key)
        let store = DismissedStaleAppStore(defaults: defaults)
        #expect(store.allBundleIDs().isEmpty)
    }

    @Test func removeAllClearsInMemoryAndPersistedBundleIDsIdempotently() {
        let defaults = fresh()
        let store = DismissedStaleAppStore(defaults: defaults)
        store.skipForever(bundleID: "com.example.app")

        store.removeAll()

        #expect(store.allBundleIDs().isEmpty)
        #expect(DismissedStaleAppStore(defaults: defaults).allBundleIDs().isEmpty)

        store.removeAll()

        #expect(store.allBundleIDs().isEmpty)
        #expect(DismissedStaleAppStore(defaults: defaults).allBundleIDs().isEmpty)
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "dismiss-stale-test-\(UUID().uuidString)")!
    }
}
