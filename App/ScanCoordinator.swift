import Foundation
import PermissionsCore
import PermissionsScanners
import PermissionsUI

@MainActor
final class ScanCoordinator {
    private let viewModel: AppViewModel
    private let tccScanner: any TCCScanner
    private let launchAgentScanner: any LaunchAgentScanner

    init(
        viewModel: AppViewModel,
        tccScanner: any TCCScanner = MockTCCScanner(),
        launchAgentScanner: any LaunchAgentScanner = MockLaunchAgentScanner()
    ) {
        self.viewModel = viewModel
        self.tccScanner = tccScanner
        self.launchAgentScanner = launchAgentScanner
    }

    func runMockScan() async {
        do {
            let grants = try await tccScanner.scan()
            let items = try await launchAgentScanner.scan()
            viewModel.grants = grants
            viewModel.launchAgents = items
            viewModel.dataSource = .mock
        } catch {
            // Scaffold path: scanners are mocks and don't throw. Real scanners
            // surface errors into the UI via a follow-up slice.
            assertionFailure("Mock scan threw, which should never happen: \(error)")
        }
    }
}
