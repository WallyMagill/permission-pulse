import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite("Export coverage") @MainActor
struct ExportReportBuilderTests {
    private let environment = ExportEnvironment(appVersion: "0.7.2", appBuild: "42", macOSVersion: "27.2.0")

    @Test("A reduced Permissions scan exports as reduced with the hidden services")
    func reducedPermissions() {
        let vm = AppViewModel(tccAvailability: .complete(lastUpdated: Date(timeIntervalSince1970: 0)))
        vm.tccUnavailableSources = [.userTCCDatabase]
        let coverage = ExportReportBuilder.report(from: vm, environment: environment, generatedAt: Date()).coverage
        #expect(coverage.permissions.coverage == .reduced)
        #expect(coverage.permissions.unavailableServices.contains("camera"))
        #expect(!coverage.permissions.unavailableServices.contains("accessibility"))
    }

    @Test("Failures keep the last success and say why")
    func failures() {
        let denied = ExportReportBuilder.coverage(.failed(lastSuccessful: nil, error: .permissionDenied(reason: "x")))
        #expect(denied == ExportDomainCoverage(coverage: .failed, lastSuccessfulScan: nil, failureReason: .fullDiskAccessOff))
        let folder = ExportReportBuilder.coverage(
            .failed(lastSuccessful: Date(timeIntervalSince1970: 5), error: .permissionDenied(reason: "x")),
            needsFullDiskAccess: false
        )
        #expect(folder.failureReason == .sourceUnavailable)
        #expect(folder.lastSuccessfulScan == Date(timeIntervalSince1970: 5))
        #expect(ExportReportBuilder.coverage(.never).failureReason == .notScannedYet)
    }

    @Test("Stale Apps exports why it wasn't checked, like the page's empty states")
    func staleAppsStatus() {
        let vm = AppViewModel(tccAvailability: .complete(lastUpdated: Date(timeIntervalSince1970: 0)))
        vm.snapshotStoreProblem = .corrupt
        #expect(ExportReportBuilder.staleAppsStatus(vm) == .historyUnavailable)
        vm.snapshotStoreProblem = nil
        vm.latestSnapshotID = SnapshotID(rawValue: 1)
        #expect(ExportReportBuilder.staleAppsStatus(vm) == .checked)
        #expect(ExportReportBuilder.staleAppsStatus(AppViewModel()) == .permissionsNotScanned)
    }
}
