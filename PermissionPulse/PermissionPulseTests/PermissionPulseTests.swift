//
//  PermissionPulseTests.swift
//  PermissionPulseTests
//
//  Created by Wally Magill on 5/13/26.
//

import Foundation
import PermissionsCore
import PermissionsScanners
import PermissionsStore
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
    @Test func scanFailurePresentationIsActionableAndDistinctFromStorageFailure() {
        var presentedMessages: [String] = []
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(
                environment: ["PERMISSION_PULSE_TEST_MODE": "1"]
            ),
            resetMessagePresenter: { presentedMessages.append($0) }
        )

        delegate.handleResetResult(.completed(scanSucceeded: false))
        delegate.handleResetResult(.failed(
            phase: .deleteHistory,
            message: "injected storage failure"
        ))

        #expect(presentedMessages.count == 2)
        #expect(presentedMessages[0].localizedCaseInsensitiveContains("Refresh"))
        #expect(presentedMessages[0] != presentedMessages[1])
    }

    @Test func testModeConstructsStoresWithIsolatedDefaults() throws {
        let expectedTestSuite =
            "com.wallymagill.permissionpulse.test-host.\(ProcessInfo.processInfo.processIdentifier)"
        let observedDefaults = try #require(UserDefaults(suiteName: expectedTestSuite))
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(
                environment: ["PERMISSION_PULSE_TEST_MODE": "1"]
            )
        )
        let preferenceKey = PreferencesStore.snapshotRetentionDaysKey
        let dismissedDiffKey = DismissedDiffEntryStore.key
        let dismissedStaleKey = DismissedStaleAppStore.key

        defer {
            observedDefaults.removePersistentDomain(forName: expectedTestSuite)
        }

        #expect(AppDelegate.testDefaultsSuiteName == expectedTestSuite)

        delegate.preferencesStore.snapshotRetentionDays = 123
        delegate.dismissedDiffEntries.dismissForever(key: "test-entry")
        delegate.dismissedStaleApps.skipForever(bundleID: "com.example.test")

        #expect(observedDefaults.integer(forKey: preferenceKey) == 123)
        #expect(observedDefaults.data(forKey: dismissedDiffKey) != nil)
        #expect(
            observedDefaults.array(forKey: dismissedStaleKey) as? [String]
                == ["com.example.test"]
        )
    }

    @Test func overlappingResetRequestsStartOnlyOneOperation() async {
        let gate = SuspendingResetOperation()
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(
                environment: ["PERMISSION_PULSE_TEST_MODE": "1"]
            ),
            resetOperation: { await gate.run() }
        )

        delegate.requestResetAllData()
        await gate.waitUntilRunning()
        delegate.requestResetAllData()

        #expect(await gate.invocationCount == 1)

        await gate.resume()
        await delegate.waitForResetCompletion()
        #expect(await gate.invocationCount == 1)
    }

    @Test func resetReleasesAndReconstructsLiveSnapshotRuntime() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-delegate-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("snapshots.db")
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
        let delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(
                environment: ["PERMISSION_PULSE_TEST_MODE": "1"]
            ),
            weeklyDigestScheduler: scheduler
        )
        delegate.installSnapshotRuntime(
            try SnapshotStore(path: databaseURL.path(percentEncoded: false))
        )
        #expect(delegate.hasSnapshotRuntime)

        var checkedFirstRemoval = false
        var runtimeWasReleasedBeforeDeletion = false
        let fileManager = ObservingResetFileManager { _ in
            guard !checkedFirstRemoval else { return }
            checkedFirstRemoval = true
            let references = delegate.snapshotRuntimeReferences
            runtimeWasReleasedBeforeDeletion = !references.hasStore
                && !references.hasCoordinator
        }

        let result = await delegate.performReset(
            at: databaseURL,
            fileManager: fileManager,
            rescan: { true }
        )

        #expect(result == .completed(scanSucceeded: true))
        #expect(runtimeWasReleasedBeforeDeletion)
        #expect(delegate.hasSnapshotRuntime)

        delegate.preferencesStore.staleThresholdDays = 137
        await delegate.updateSnapshotHistoryAfterScan()
        #expect(delegate.viewModel.staleThresholdDays == 137)
    }
}

private actor SuspendingResetOperation {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isRunning = false
    private(set) var invocationCount = 0

    func run() async {
        invocationCount += 1
        isRunning = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRunning() async {
        guard !isRunning else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
        isRunning = false
    }
}

@MainActor
private final class ObservingResetFileManager: ResetFileManaging {
    private let onRemove: @MainActor (URL) -> Void

    init(onRemove: @MainActor @escaping (URL) -> Void) {
        self.onRemove = onRemove
    }

    func removeItem(at url: URL) throws {
        onRemove(url)
        try FileManager.default.removeItem(at: url)
    }
}
