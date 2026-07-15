import Foundation
import Testing
@testable import PermissionsUI

@Suite @MainActor struct DismissedStaleAppStoreTests {
    @Test func skipForeverPersistsAcrossInits() {
        let defaults = fresh()
        let writer = DismissedStaleAppStore(defaults: defaults)
        writer.skipForever(stableKey: "bundle:com.example.app")

        let reader = DismissedStaleAppStore(defaults: defaults)
        #expect(reader.contains(stableKey: "bundle:com.example.app"))
    }

    @Test func unskipRemovesStableKey() {
        let defaults = fresh()
        let store = DismissedStaleAppStore(defaults: defaults)
        store.skipForever(stableKey: "bundle:a")
        store.skipForever(stableKey: "bundle:b")

        store.unskip(stableKey: "bundle:a")

        let reader = DismissedStaleAppStore(defaults: defaults)
        #expect(!reader.contains(stableKey: "bundle:a"))
        #expect(reader.contains(stableKey: "bundle:b"))
    }

    @Test func corruptDefaultsReadsAsEmpty() {
        let defaults = fresh()
        defaults.set(42, forKey: DismissedStaleAppStore.key)
        let store = DismissedStaleAppStore(defaults: defaults)
        #expect(store.allStableKeys().isEmpty)
    }

    @Test func removeAllClearsInMemoryAndPersistedStableKeysIdempotently() {
        let defaults = fresh()
        let store = DismissedStaleAppStore(defaults: defaults)
        store.skipForever(stableKey: "bundle:com.example.app")

        store.removeAll()

        #expect(store.allStableKeys().isEmpty)
        #expect(DismissedStaleAppStore(defaults: defaults).allStableKeys().isEmpty)

        store.removeAll()

        #expect(store.allStableKeys().isEmpty)
        #expect(DismissedStaleAppStore(defaults: defaults).allStableKeys().isEmpty)
    }

    @Test func mixedLegacyKeysMigrateInMemoryAndPersistDeterministically() throws {
        let defaults = fresh()
        defaults.set(
            ["path:/Applications/Path Only.app", "com.example.legacy", "bundle:com.example.current"],
            forKey: DismissedStaleAppStore.key
        )

        let store = DismissedStaleAppStore(defaults: defaults)

        #expect(store.contains(stableKey: "bundle:com.example.legacy"))
        #expect(store.contains(stableKey: "bundle:com.example.current"))
        #expect(store.contains(stableKey: "path:/Applications/Path Only.app"))

        store.skipForever(stableKey: "bundle:com.example.added")

        let persisted = try #require(defaults.stringArray(forKey: DismissedStaleAppStore.key))
        #expect(persisted == [
            "bundle:com.example.added",
            "bundle:com.example.current",
            "bundle:com.example.legacy",
            "path:/Applications/Path Only.app",
        ])
    }

    @Test func migratedKeysRemainPrefixedAfterReloadAndAnotherPersistence() throws {
        let defaults = fresh()
        defaults.set(["com.example.legacy", "path:/Applications/Tool.app"], forKey: DismissedStaleAppStore.key)

        let first = DismissedStaleAppStore(defaults: defaults)
        first.skipForever(stableKey: "bundle:com.example.added")
        let second = DismissedStaleAppStore(defaults: defaults)
        second.skipForever(stableKey: "bundle:com.example.second")

        let persisted = try #require(defaults.stringArray(forKey: DismissedStaleAppStore.key))
        #expect(persisted == [
            "bundle:com.example.added",
            "bundle:com.example.legacy",
            "bundle:com.example.second",
            "path:/Applications/Tool.app",
        ])
        #expect(second.allStableKeys() == Set(persisted))
    }

    @Test func pathStableKeysRemainIndependent() {
        let defaults = fresh()
        let store = DismissedStaleAppStore(defaults: defaults)

        store.skipForever(stableKey: "path:/Applications/Tool A.app")

        #expect(store.contains(stableKey: "path:/Applications/Tool A.app"))
        #expect(!store.contains(stableKey: "path:/Applications/Tool B.app"))
    }

    @Test func corruptMixedEntryDoesNotDiscardValidKeys() {
        let defaults = fresh()
        defaults.set(["com.example.legacy", 42, "path:/Applications/Tool.app"], forKey: DismissedStaleAppStore.key)

        let store = DismissedStaleAppStore(defaults: defaults)

        #expect(store.allStableKeys() == [
            "bundle:com.example.legacy",
            "path:/Applications/Tool.app",
        ])
    }

    @Test func legacyBundleProjectionIsSortedReadOnlyAndExcludesPathKeys() throws {
        let defaults = fresh()
        let original = [
            "path:/Applications/Path Only.app",
            "com.example.legacy",
            "bundle:com.example.current",
        ]
        defaults.set(original, forKey: DismissedStaleAppStore.key)
        let store = DismissedStaleAppStore(defaults: defaults)

        #expect(store.allBundleIDs() == [
            "com.example.current",
            "com.example.legacy",
        ])
        #expect(store.allStableKeys().contains("path:/Applications/Path Only.app"))
        #expect(try #require(defaults.stringArray(forKey: DismissedStaleAppStore.key)) == original)
    }

    // MARK: - Helpers

    private func fresh() -> UserDefaults {
        UserDefaults(suiteName: "dismiss-stale-test-\(UUID().uuidString)")!
    }
}
