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
    private let btmScanner: any BTMScanner
    private let btmDataSource: AppViewModel.DataSource

    init(
        viewModel: AppViewModel,
        tccScanner: any TCCScanner = TCCScannerSQLite(),
        tccDataSource: AppViewModel.DataSource = .live,
        launchAgentScanner: any LaunchAgentScanner = LaunchAgentScannerFS(),
        launchAgentsDataSource: AppViewModel.DataSource = .live,
        btmScanner: any BTMScanner = BTMScannerDirect(),
        btmDataSource: AppViewModel.DataSource = .live
    ) {
        self.viewModel = viewModel
        self.tccScanner = tccScanner
        self.tccDataSource = tccDataSource
        self.launchAgentScanner = launchAgentScanner
        self.launchAgentsDataSource = launchAgentsDataSource
        self.btmScanner = btmScanner
        self.btmDataSource = btmDataSource
    }

    func runScan() async {
        // DataSource reflects which scanner is wired up, not whether the last
        // scan succeeded — a failed live scan (e.g. no FDA) must not leave the
        // UI claiming the data on screen is mock.
        viewModel.tccDataSource = tccDataSource
        viewModel.launchAgentsDataSource = launchAgentsDataSource
        viewModel.btmDataSource = btmDataSource

        async let tccResultTask = runTCCScan()
        async let launchAgentResultTask = runLaunchAgentScan()
        async let btmResultTask = runBTMScan()

        let tccResult = await tccResultTask
        let launchAgentResult = await launchAgentResultTask
        let btmResult = await btmResultTask

        applyTCC(tccResult)
        applyLaunchAgents(launchAgentResult)
        applyBTM(btmResult)
    }

    func rescan() async {
        await runScan()
    }

    private struct TCCScanResult: Sendable {
        let grants: [PermissionGrant]
        let error: ScannerError?
    }

    private struct LaunchAgentScanResult: Sendable {
        let items: [LaunchAgentItem]
        let error: ScannerError?
    }

    private struct BTMScanResult: Sendable {
        let items: [BTMItem]
        let error: ScannerError?
    }

    private func runTCCScan() async -> TCCScanResult {
        do {
            let grants = try await tccScanner.scan()
            return TCCScanResult(grants: grants, error: nil)
        } catch let scannerError as ScannerError {
            Self.logger.error("TCC scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return TCCScanResult(grants: [], error: scannerError)
        } catch {
            Self.logger.error("TCC scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return TCCScanResult(grants: [], error: .permissionDenied(reason: error.localizedDescription))
        }
    }

    private func runLaunchAgentScan() async -> LaunchAgentScanResult {
        do {
            let items = try await launchAgentScanner.scan()
            return LaunchAgentScanResult(items: items, error: nil)
        } catch let scannerError as ScannerError {
            Self.logger.error("LaunchAgent scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return LaunchAgentScanResult(items: [], error: scannerError)
        } catch {
            Self.logger.error("LaunchAgent scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return LaunchAgentScanResult(items: [], error: .permissionDenied(reason: error.localizedDescription))
        }
    }

    private func runBTMScan() async -> BTMScanResult {
        do {
            let items = try await btmScanner.scan()
            return BTMScanResult(items: items, error: nil)
        } catch let scannerError as ScannerError {
            Self.logger.error("BTM scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return BTMScanResult(items: [], error: scannerError)
        } catch {
            Self.logger.error("BTM scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return BTMScanResult(items: [], error: .permissionDenied(reason: error.localizedDescription))
        }
    }

    private func applyTCC(_ result: TCCScanResult) {
        if let error = result.error {
            viewModel.tccScanError = error
        } else {
            viewModel.grants = result.grants
            viewModel.tccScanError = nil
        }
    }

    private func applyLaunchAgents(_ result: LaunchAgentScanResult) {
        if let error = result.error {
            viewModel.launchAgentScanError = error
        } else {
            viewModel.launchAgents = result.items
            viewModel.launchAgentScanError = nil
        }
    }

    private func applyBTM(_ result: BTMScanResult) {
        if let error = result.error {
            viewModel.btmScanError = error
        } else {
            viewModel.btmItems = result.items
            viewModel.btmScanError = nil
        }
    }
}
