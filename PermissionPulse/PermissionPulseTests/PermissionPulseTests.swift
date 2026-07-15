//
//  PermissionPulseTests.swift
//  PermissionPulseTests
//
//  Created by Wally Magill on 5/13/26.
//

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
