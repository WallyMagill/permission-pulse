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
