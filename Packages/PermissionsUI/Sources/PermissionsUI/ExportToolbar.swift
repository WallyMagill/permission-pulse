// AppKit: NSSavePanel is the only way to let the user choose an export
// location; writing there is explicitly allowed by the read-only hard rules.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PermissionsCore

struct ExportToolbarMenu: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Menu {
            Button(String(localized: "Export as JSON…")) { export(.json) }
            Button(String(localized: "Export as Markdown…")) { export(.markdown) }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .help(String(localized: "Export current state"))
        .accessibilityLabel(String(localized: "Export"))
    }

    private enum Format { case json, markdown }

    private func export(_ format: Format) {
        let report = ExportReportBuilder.report(
            from: viewModel,
            environment: ExportReportBuilder.runningEnvironment(),
            generatedAt: Date()
        )
        do {
            let data: Data
            let ext: String
            let contentType: UTType
            switch format {
            case .json:
                data = try PermissionsExport.makeJSON(report: report)
                ext = "json"; contentType = .json
            case .markdown:
                data = Data(PermissionsExport.makeMarkdown(report: report).utf8)
                ext = "md"; contentType = UTType(filenameExtension: "md") ?? .plainText
            }
            try ExportSaver.run(data: data, suggestedName: "PermissionPulse-Export.\(ext)", contentType: contentType)
        } catch {
            // AppKit: NSAlert is the idiomatic one-shot modal for surfacing a
            // failed encode/write so the export never fails silently.
            NSAlert(error: error).runModal()
        }
    }
}

@MainActor
private enum ExportSaver {
    // AppKit: NSSavePanel + Data.write to the user-chosen URL. A cancel is not
    // an error (returns without writing); a real write failure propagates.
    static func run(data: Data, suggestedName: String, contentType: UTType) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: .atomic)
    }
}

/// Turns the view model's scan state into the export's coverage record.
enum ExportReportBuilder {
    @MainActor
    static func report(from viewModel: AppViewModel, environment: ExportEnvironment, generatedAt: Date) -> ExportReport {
        let scope = viewModel.permissionScope
        let hidden = PermissionService.allCases.filter(scope.isHidden).map(\.rawValue)
        return PermissionsExport.report(
            grants: viewModel.grants,
            launchAgents: viewModel.launchAgents,
            btmItems: viewModel.btmItems,
            staleApps: viewModel.staleApps,
            generatedAt: generatedAt,
            environment: environment,
            coverage: ExportCoverage(
                permissions: coverage(viewModel.tccAvailability, unavailableServices: hidden),
                launchAgents: coverage(viewModel.launchAgentAvailability, needsFullDiskAccess: false),
                backgroundItems: coverage(viewModel.btmAvailability)
            ),
            staleAppsStatus: staleAppsStatus(viewModel)
        )
    }

    /// The same reasons the Stale Apps page gives for an empty list.
    @MainActor
    static func staleAppsStatus(_ viewModel: AppViewModel) -> ExportStaleAppsStatus {
        let state = StaleAppsEmptyState.resolve(
            hasPermissionData: viewModel.hasPermissionData,
            historyAvailable: !viewModel.snapshotStoreUnavailable && viewModel.latestSnapshotID != nil,
            systemLevelOnly: viewModel.permissionScope.isReduced
        )
        return switch state {
        case .noPermissionData: .permissionsNotScanned
        case .historyUnavailable: .historyUnavailable
        case .noneStale: .checked
        }
    }

    /// A Launch Agents "permission denied" is an unreadable folder, not Full
    /// Disk Access, so only the FDA-gated domains report `fullDiskAccessOff`.
    static func coverage(
        _ availability: ScanAvailability,
        unavailableServices: [String] = [],
        needsFullDiskAccess: Bool = true
    ) -> ExportDomainCoverage {
        let level: ExportDomainCoverage.Level
        var reason: ExportDomainCoverage.FailureReason?
        switch availability {
        case .never:
            level = .failed
            reason = .notScannedYet
        case .complete:
            level = unavailableServices.isEmpty ? .complete : .reduced
        case .degraded:
            level = .degraded
        case .failed(_, let error):
            level = .failed
            reason = failureReason(error, needsFullDiskAccess: needsFullDiskAccess)
        }
        return ExportDomainCoverage(
            coverage: level,
            lastSuccessfulScan: availability.lastSuccessful,
            unavailableServices: unavailableServices,
            failureReason: reason
        )
    }

    private static func failureReason(
        _ error: ScannerError,
        needsFullDiskAccess: Bool
    ) -> ExportDomainCoverage.FailureReason {
        switch error {
        case .permissionDenied: needsFullDiskAccess ? .fullDiskAccessOff : .sourceUnavailable
        case .schemaMismatch, .unsupportedOnThisOS: .unrecognizedFormat
        case .temporarilyUnavailable: .sourceUnavailable
        }
    }

    static func runningEnvironment() -> ExportEnvironment {
        let app = AppVersion.running
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return ExportEnvironment(
            appVersion: app.shortVersion,
            appBuild: app.build,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        )
    }
}
