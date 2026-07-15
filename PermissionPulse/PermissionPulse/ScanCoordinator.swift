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
    private let now: @Sendable () -> Date

    init(
        viewModel: AppViewModel,
        tccScanner: any TCCScanner = TCCScannerSQLite(),
        tccDataSource: AppViewModel.DataSource = .live,
        launchAgentScanner: any LaunchAgentScanner = LaunchAgentScannerFS(),
        launchAgentsDataSource: AppViewModel.DataSource = .live,
        btmScanner: any BTMScanner = BTMScannerDirect(),
        btmDataSource: AppViewModel.DataSource = .live,
        now: @Sendable @escaping () -> Date = Date.init
    ) {
        self.viewModel = viewModel
        self.tccScanner = tccScanner
        self.tccDataSource = tccDataSource
        self.launchAgentScanner = launchAgentScanner
        self.launchAgentsDataSource = launchAgentsDataSource
        self.btmScanner = btmScanner
        self.btmDataSource = btmDataSource
        self.now = now
    }

    func runScan() async {
        // One timestamp describes the evidence boundary across every domain.
        let scanDate = now()

        // DataSource reflects which scanner is wired up, not whether the last
        // scan succeeded.
        viewModel.tccDataSource = tccDataSource
        viewModel.launchAgentsDataSource = launchAgentsDataSource
        viewModel.btmDataSource = btmDataSource

        async let tccResultTask = runTCCScan()
        async let launchAgentResultTask = runLaunchAgentScan()
        async let btmResultTask = runBTMScan()

        let tccResult = await tccResultTask
        let launchAgentResult = await launchAgentResultTask
        let btmResult = await btmResultTask

        applyTCC(tccResult, at: scanDate)
        applyLaunchAgents(launchAgentResult, at: scanDate)
        applyBTM(btmResult, at: scanDate)
    }

    func rescan() async {
        await runScan()
    }

    private enum DomainScanResult<Item: Sendable>: Sendable {
        case output(ScannerOutput<Item>)
        case failure(ScannerError)
    }

    private func runTCCScan() async -> DomainScanResult<PermissionGrant> {
        do {
            return .output(try await tccScanner.scan())
        } catch let scannerError as ScannerError {
            Self.logger.error("TCC scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return .failure(scannerError)
        } catch {
            Self.logger.error("TCC scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return .failure(.temporarilyUnavailable(reason: error.localizedDescription))
        }
    }

    private func runLaunchAgentScan() async -> DomainScanResult<LaunchAgentItem> {
        do {
            return .output(try await launchAgentScanner.scan())
        } catch let scannerError as ScannerError {
            Self.logger.error("LaunchAgent scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return .failure(scannerError)
        } catch {
            Self.logger.error("LaunchAgent scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return .failure(.temporarilyUnavailable(reason: error.localizedDescription))
        }
    }

    private func runBTMScan() async -> DomainScanResult<BTMItem> {
        do {
            return .output(try await btmScanner.scan())
        } catch let scannerError as ScannerError {
            Self.logger.error("BTM scan failed: \(scannerError.localizedDescription, privacy: .public)")
            return .failure(scannerError)
        } catch {
            Self.logger.error("BTM scan failed with unexpected error: \(error.localizedDescription, privacy: .public)")
            return .failure(.temporarilyUnavailable(reason: error.localizedDescription))
        }
    }

    private func applyTCC(_ result: DomainScanResult<PermissionGrant>, at scanDate: Date) {
        switch result {
        case .output(let output):
            viewModel.grants = output.items
            viewModel.tccAvailability = availability(for: output.warnings, at: scanDate)
        case .failure(let error):
            viewModel.tccAvailability = .failed(
                lastSuccessful: viewModel.tccAvailability.lastSuccessful,
                error: error
            )
        }
    }

    private func applyLaunchAgents(
        _ result: DomainScanResult<LaunchAgentItem>,
        at scanDate: Date
    ) {
        switch result {
        case .output(let output):
            viewModel.launchAgents = output.items
            viewModel.launchAgentAvailability = availability(for: output.warnings, at: scanDate)
        case .failure(let error):
            viewModel.launchAgentAvailability = .failed(
                lastSuccessful: viewModel.launchAgentAvailability.lastSuccessful,
                error: error
            )
        }
    }

    private func applyBTM(_ result: DomainScanResult<BTMItem>, at scanDate: Date) {
        switch result {
        case .output(let output):
            viewModel.btmItems = output.items
            viewModel.btmAvailability = availability(for: output.warnings, at: scanDate)
        case .failure(let error):
            viewModel.btmAvailability = .failed(
                lastSuccessful: viewModel.btmAvailability.lastSuccessful,
                error: error
            )
        }
    }

    private func availability(for warnings: [ScannerWarning], at scanDate: Date) -> ScanAvailability {
        warnings.isEmpty
            ? .complete(lastUpdated: scanDate)
            : .degraded(lastUpdated: scanDate, warnings: warnings)
    }
}
