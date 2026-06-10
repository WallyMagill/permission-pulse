import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ScanCoordinatorTests {
    private struct ThrowingLaunchAgentScanner: LaunchAgentScanner {
        func scan() async throws -> [LaunchAgentItem] {
            throw ScannerError.permissionDenied(reason: "boom")
        }
    }

    private struct ThrowingTCCScanner: TCCScanner {
        func scan() async throws -> [PermissionGrant] {
            throw ScannerError.permissionDenied(reason: "no FDA")
        }
    }

    private struct ThrowingBTMScanner: BTMScanner {
        func scan() async throws -> [BTMItem] {
            throw ScannerError.permissionDenied(reason: "no FDA")
        }
    }

    // The Mock badge must mean "a Mock scanner produced this data", not
    // "the last live scan failed" — a no-FDA first launch keeps every scan
    // erroring forever and must not pin the badge on real data.
    @Test func dataSourceReflectsConfiguredScannerEvenWhenScanFails() async throws {
        let vm = AppViewModel()
        #expect(vm.tccDataSource == .mock)
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: ThrowingTCCScanner(),
            tccDataSource: .live,
            launchAgentScanner: MockLaunchAgentScanner(),
            launchAgentsDataSource: .live,
            btmScanner: ThrowingBTMScanner(),
            btmDataSource: .live
        )
        await coordinator.runScan()
        #expect(vm.tccDataSource == .live)
        #expect(vm.launchAgentsDataSource == .live)
        #expect(vm.btmDataSource == .live)
        #expect(vm.tccScanError != nil)
        #expect(vm.btmScanError != nil)
    }

    @Test func launchAgentScanErrorSurfacedToViewModel() async throws {
        let vm = AppViewModel()
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: MockTCCScanner(),
            launchAgentScanner: ThrowingLaunchAgentScanner(),
            btmScanner: MockBTMScanner()
        )
        await coordinator.runScan()
        guard case .permissionDenied(let reason)? = vm.launchAgentScanError else {
            Issue.record("Expected launchAgentScanError to be set"); return
        }
        #expect(reason == "boom")
    }

    @Test func launchAgentScanErrorClearedOnSuccess() async throws {
        let vm = AppViewModel(launchAgentScanError: .permissionDenied(reason: "stale"))
        let coordinator = ScanCoordinator(
            viewModel: vm,
            tccScanner: MockTCCScanner(),
            launchAgentScanner: MockLaunchAgentScanner(),
            btmScanner: MockBTMScanner()
        )
        await coordinator.runScan()
        #expect(vm.launchAgentScanError == nil)
        #expect(!vm.launchAgents.isEmpty)
    }
}
