import Foundation
import OSLog
import PermissionsCore
import PermissionsScanners
import PermissionsUI

@MainActor
final class ScanCoordinator {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "scan-coordinator"
    )

    private let viewModel: AppViewModel
    private let tccScanner: any TCCScanner
    private let tccDataSource: AppViewModel.DataSource
    private let launchAgentScanner: any LaunchAgentScanner
    private let launchAgentsDataSource: AppViewModel.DataSource

    init(
        viewModel: AppViewModel,
        tccScanner: any TCCScanner = TCCScannerSQLite(),
        tccDataSource: AppViewModel.DataSource = .live,
        launchAgentScanner: any LaunchAgentScanner = LaunchAgentScannerFS(),
        launchAgentsDataSource: AppViewModel.DataSource = .live
    ) {
        self.viewModel = viewModel
        self.tccScanner = tccScanner
        self.tccDataSource = tccDataSource
        self.launchAgentScanner = launchAgentScanner
        self.launchAgentsDataSource = launchAgentsDataSource
    }

    func runScan() async {
        do {
            let grants = try await tccScanner.scan()
            viewModel.grants = grants
            viewModel.tccDataSource = tccDataSource
            viewModel.tccScanError = nil
        } catch let scannerError as ScannerError {
            Self.logger.error("TCC scan failed: \(scannerError.localizedDescription, privacy: .public)")
            viewModel.tccScanError = scannerError
        } catch {
            Self.logger.error("TCC scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            viewModel.tccScanError = .permissionDenied(reason: error.localizedDescription)
        }

        do {
            let items = try await launchAgentScanner.scan()
            viewModel.launchAgents = items
            viewModel.launchAgentsDataSource = launchAgentsDataSource
        } catch {
            Self.logger.error("LaunchAgent scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func rescan() async {
        await runScan()
    }
}
