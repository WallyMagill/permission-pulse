import Foundation
import Testing
import PermissionsCore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ScanCoordinatorTests {
    @Test func completeOutputsReplaceAllListsAndUseOneCapturedTimestamp() async {
        let scanDate = Date(timeIntervalSince1970: 1_725_000_000)
        let oldGrant = grant(bundleID: "com.example.old")
        let newGrant = grant(bundleID: "com.example.new")
        let oldAgent = launchAgent(label: "com.example.old")
        let newAgent = launchAgent(label: "com.example.new")
        let oldBTM = btm(identifier: "old")
        let newBTM = btm(identifier: "new")
        let vm = AppViewModel(
            grants: [oldGrant],
            launchAgents: [oldAgent],
            btmItems: [oldBTM]
        )
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: StaticTCCScanner(output: .init(items: [newGrant])),
            launchAgentScanner: StaticLaunchAgentScanner(output: .init(items: [newAgent])),
            btmScanner: StaticBTMScanner(output: .init(items: [newBTM])),
            now: { scanDate }
        )

        await coordinator.runScan()

        #expect(vm.grants == [newGrant])
        #expect(vm.launchAgents == [newAgent])
        #expect(vm.btmItems == [newBTM])
        #expect(vm.tccAvailability == .complete(lastUpdated: scanDate))
        #expect(vm.launchAgentAvailability == .complete(lastUpdated: scanDate))
        #expect(vm.btmAvailability == .complete(lastUpdated: scanDate))
    }

    @Test func degradedOutputsReplaceListsAndRetainEveryWarning() async {
        let scanDate = Date(timeIntervalSince1970: 1_725_000_001)
        let tccWarnings = [
            ScannerWarning(source: .userTCCDatabase),
            ScannerWarning(source: .entries, omittedCount: 2),
        ]
        let launchWarnings = [ScannerWarning(source: .libraryLaunchDaemons)]
        let btmWarnings = [ScannerWarning(source: .entries, omittedCount: 1)]
        let newGrant = grant(bundleID: "com.example.partial")
        let newAgent = launchAgent(label: "com.example.partial")
        let newBTM = btm(identifier: "partial")
        let vm = AppViewModel(
            grants: [grant(bundleID: "com.example.old")],
            launchAgents: [launchAgent(label: "com.example.old")],
            btmItems: [btm(identifier: "old")]
        )
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: StaticTCCScanner(output: .init(items: [newGrant], warnings: tccWarnings)),
            launchAgentScanner: StaticLaunchAgentScanner(output: .init(items: [newAgent], warnings: launchWarnings)),
            btmScanner: StaticBTMScanner(output: .init(items: [newBTM], warnings: btmWarnings)),
            now: { scanDate }
        )

        await coordinator.runScan()

        #expect(vm.grants == [newGrant])
        #expect(vm.launchAgents == [newAgent])
        #expect(vm.btmItems == [newBTM])
        #expect(vm.tccAvailability == .degraded(lastUpdated: scanDate, warnings: tccWarnings))
        #expect(vm.launchAgentAvailability == .degraded(lastUpdated: scanDate, warnings: launchWarnings))
        #expect(vm.btmAvailability == .degraded(lastUpdated: scanDate, warnings: btmWarnings))
    }

    @Test func failedOutputsPreserveListsAndCarryForwardCompleteOrDegradedTimestamps() async {
        let tccDate = Date(timeIntervalSince1970: 1_700_000_000)
        let launchDate = Date(timeIntervalSince1970: 1_700_000_100)
        let btmDate = Date(timeIntervalSince1970: 1_700_000_200)
        let oldGrant = grant(bundleID: "com.example.last-known")
        let oldAgent = launchAgent(label: "com.example.last-known")
        let oldBTM = btm(identifier: "last-known")
        let tccError = ScannerError.permissionDenied(reason: "TCC denied")
        let launchError = ScannerError.temporarilyUnavailable(reason: "launchd busy")
        let btmError = ScannerError.schemaMismatch(detail: "BTM changed")
        let vm = AppViewModel(
            grants: [oldGrant],
            launchAgents: [oldAgent],
            btmItems: [oldBTM],
            tccAvailability: .complete(lastUpdated: tccDate),
            btmAvailability: .degraded(
                lastUpdated: btmDate,
                warnings: [.init(source: .entries, omittedCount: 1)]
            ),
            launchAgentAvailability: .complete(lastUpdated: launchDate)
        )
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: ThrowingTCCScanner(error: tccError),
            launchAgentScanner: ThrowingLaunchAgentScanner(error: launchError),
            btmScanner: ThrowingBTMScanner(error: btmError)
        )

        await coordinator.runScan()

        #expect(vm.grants == [oldGrant])
        #expect(vm.launchAgents == [oldAgent])
        #expect(vm.btmItems == [oldBTM])
        #expect(vm.tccAvailability == .failed(lastSuccessful: tccDate, error: tccError))
        #expect(vm.launchAgentAvailability == .failed(lastSuccessful: launchDate, error: launchError))
        #expect(vm.btmAvailability == .failed(lastSuccessful: btmDate, error: btmError))
    }

    @Test func failureAfterFailureKeepsOriginalLastSuccessfulTimestamp() async {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let firstError = ScannerError.temporarilyUnavailable(reason: "first")
        let nextError = ScannerError.temporarilyUnavailable(reason: "next")
        let vm = AppViewModel(
            tccAvailability: .failed(lastSuccessful: originalDate, error: firstError)
        )
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: ThrowingTCCScanner(error: nextError),
            launchAgentScanner: StaticLaunchAgentScanner(output: .init(items: [])),
            btmScanner: StaticBTMScanner(output: .init(items: []))
        )

        await coordinator.runScan()

        #expect(vm.tccAvailability == .failed(lastSuccessful: originalDate, error: nextError))
    }

    @Test func unknownThrownErrorsMapToTemporaryUnavailabilityForEveryDomain() async {
        let vm = AppViewModel()
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: UnknownThrowingTCCScanner(),
            launchAgentScanner: UnknownThrowingLaunchAgentScanner(),
            btmScanner: UnknownThrowingBTMScanner()
        )

        await coordinator.runScan()

        assertTemporaryFailure(vm.tccAvailability)
        assertTemporaryFailure(vm.launchAgentAvailability)
        assertTemporaryFailure(vm.btmAvailability)
    }

    // The Mock badge means which scanner is configured, not whether its scan succeeds.
    @Test func dataSourceReflectsConfiguredScannerEvenWhenScanFails() async {
        let vm = AppViewModel()
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: ThrowingTCCScanner(error: .permissionDenied(reason: "no FDA")),
            tccDataSource: .live,
            launchAgentScanner: StaticLaunchAgentScanner(output: .init(items: [])),
            launchAgentsDataSource: .live,
            btmScanner: ThrowingBTMScanner(error: .permissionDenied(reason: "no FDA")),
            btmDataSource: .live
        )

        await coordinator.runScan()

        #expect(vm.tccDataSource == .live)
        #expect(vm.launchAgentsDataSource == .live)
        #expect(vm.btmDataSource == .live)
        #expect(vm.tccScanError != nil)
        #expect(vm.btmScanError != nil)
    }

    private func assertTemporaryFailure(_ availability: ScanAvailability) {
        guard case .failed(lastSuccessful: nil, error: .temporarilyUnavailable(let reason)) = availability else {
            Issue.record("Expected failed temporary-unavailability state")
            return
        }
        #expect(!reason.isEmpty)
    }
}

private struct StaticTCCScanner: TCCScanner {
    let output: ScannerOutput<PermissionGrant>
    func scan() async throws -> ScannerOutput<PermissionGrant> { output }
}

private struct StaticLaunchAgentScanner: LaunchAgentScanner {
    let output: ScannerOutput<LaunchAgentItem>
    func scan() async throws -> ScannerOutput<LaunchAgentItem> { output }
}

private struct StaticBTMScanner: BTMScanner {
    let output: ScannerOutput<BTMItem>
    func scan() async throws -> ScannerOutput<BTMItem> { output }
}

private struct ThrowingTCCScanner: TCCScanner {
    let error: ScannerError
    func scan() async throws -> ScannerOutput<PermissionGrant> { throw error }
}

private struct ThrowingLaunchAgentScanner: LaunchAgentScanner {
    let error: ScannerError
    func scan() async throws -> ScannerOutput<LaunchAgentItem> { throw error }
}

private struct ThrowingBTMScanner: BTMScanner {
    let error: ScannerError
    func scan() async throws -> ScannerOutput<BTMItem> { throw error }
}

private enum UnexpectedScanError: Error { case unavailable }

private struct UnknownThrowingTCCScanner: TCCScanner {
    func scan() async throws -> ScannerOutput<PermissionGrant> { throw UnexpectedScanError.unavailable }
}

private struct UnknownThrowingLaunchAgentScanner: LaunchAgentScanner {
    func scan() async throws -> ScannerOutput<LaunchAgentItem> { throw UnexpectedScanError.unavailable }
}

private struct UnknownThrowingBTMScanner: BTMScanner {
    func scan() async throws -> ScannerOutput<BTMItem> { throw UnexpectedScanError.unavailable }
}

private func grant(bundleID: String) -> PermissionGrant {
    PermissionGrant(
        service: .microphone,
        app: .init(bundleID: bundleID, displayName: bundleID),
        lastModified: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func launchAgent(label: String) -> LaunchAgentItem {
    LaunchAgentItem(
        label: label,
        sourceDirectory: .userLaunchAgents,
        programPath: "/bin/demo",
        programArguments: [],
        runAtLoad: true,
        keepAlive: false
    )
}

private func btm(identifier: String) -> BTMItem {
    BTMItem(
        identifier: identifier,
        name: identifier,
        developerName: nil,
        bundleIdentifier: "com.example.\(identifier)",
        teamIdentifier: nil,
        type: .app,
        disposition: .enabled,
        scope: .user,
        modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
