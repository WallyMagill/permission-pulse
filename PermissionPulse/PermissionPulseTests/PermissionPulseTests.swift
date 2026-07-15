//
//  PermissionPulseTests.swift
//  PermissionPulseTests
//
//  Created by Wally Magill on 5/13/26.
//

import Foundation
import PermissionsUI
import Testing
@testable import PermissionPulse

struct PermissionPulseTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}

@Suite struct AppRuntimeEnvironmentTests {
    @Test func explicitTestModeIsDetected() {
        #expect(AppRuntimeEnvironment(environment: ["PERMISSION_PULSE_TEST_MODE": "1"]).isRunningTests)
    }

    @Test func xctestConfigurationIsDetected() {
        #expect(AppRuntimeEnvironment(environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]).isRunningTests)
    }

    @Test func ordinaryLaunchIsNotTestMode() {
        #expect(!AppRuntimeEnvironment(environment: [:]).isRunningTests)
    }
}

@Suite @MainActor struct AppDelegateRuntimeIsolationTests {
    @Test func testModeConstructsStoresWithIsolatedDefaults() {
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(
                environment: ["PERMISSION_PULSE_TEST_MODE": "1"]
            )
        )
        let preferenceKey = PreferencesStore.snapshotRetentionDaysKey
        let dismissedDiffKey = DismissedDiffEntryStore.key
        let dismissedStaleKey = DismissedStaleAppStore.key

        defer {
            delegate.runtimeDefaults.removeObject(forKey: preferenceKey)
            delegate.runtimeDefaults.removeObject(forKey: dismissedDiffKey)
            delegate.runtimeDefaults.removeObject(forKey: dismissedStaleKey)
        }

        #expect(delegate.runtimeDefaults !== UserDefaults.standard)

        delegate.preferencesStore.snapshotRetentionDays = 123
        delegate.dismissedDiffEntries.dismissForever(key: "test-entry")
        delegate.dismissedStaleApps.skipForever(bundleID: "com.example.test")

        #expect(delegate.runtimeDefaults.integer(forKey: preferenceKey) == 123)
        #expect(delegate.runtimeDefaults.data(forKey: dismissedDiffKey) != nil)
        #expect(
            delegate.runtimeDefaults.array(forKey: dismissedStaleKey) as? [String]
                == ["com.example.test"]
        )
    }
}
