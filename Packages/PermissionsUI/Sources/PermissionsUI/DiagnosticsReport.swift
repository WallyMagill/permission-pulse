import Foundation
import PermissionsCore
import PermissionsStore

/// Plain text for Preferences → Data → Copy Diagnostics: the app's own state
/// only. It never includes an item's name, bundle identifier, label or path,
/// or a scanner error's message (which can carry a path) — only counts, kinds
/// and this copy's own location.
///
/// Keys and values stay in English on purpose: the text is pasted into bug
/// reports for the maintainer, not read in the app.
public struct DiagnosticsReport: Sendable {
    public struct Domain: Sendable {
        public let name: String
        public let availability: ScanAvailability
        public let coverage: SnapshotCoverage?
        public let unavailableSources: [ScannerSource]
        public let itemCount: Int
    }

    public var appVersion: AppVersion
    public var bundlePath: String
    public var isTranslocated: Bool
    public var osVersion: String
    public var architecture: String
    public var domains: [Domain]
    public var lastScanDate: Date?
    public var latestSnapshotID: SnapshotID?
    public var latestSnapshotDate: Date?
    public var schemaVersion: Int?
    public var storeProblem: SnapshotStoreProblem?
    public var digestEnabled: Bool
    public var changeAlertsEnabled: Bool
    public var notificationAuthorization: DigestAuthorizationStatus
    public var launchAtLogin: LaunchAtLoginStatus

    /// `latestCoverage` is the stored coverage of the latest snapshot.
    @MainActor
    public init(
        viewModel: AppViewModel,
        preferences: PreferencesStore,
        appVersion: AppVersion,
        bundlePath: String,
        home: String = NSHomeDirectory(),
        osVersion: String,
        architecture: String,
        latestCoverage: SnapshotDomainCoverage?,
        schemaVersion: Int?,
        notificationAuthorization: DigestAuthorizationStatus,
        launchAtLogin: LaunchAtLoginStatus
    ) {
        self.appVersion = appVersion
        self.bundlePath = AppLocation.displayPath(bundlePath, home: home)
        self.isTranslocated = AppLocation.isTranslocated(bundlePath)
        self.osVersion = osVersion
        self.architecture = architecture
        self.domains = [
            Domain(name: "permissions", availability: viewModel.tccAvailability, coverage: latestCoverage?.tcc,
                   unavailableSources: viewModel.tccUnavailableSources, itemCount: viewModel.grants.count),
            Domain(name: "backgroundItems", availability: viewModel.btmAvailability, coverage: latestCoverage?.btm,
                   unavailableSources: [], itemCount: viewModel.btmItems.count),
            Domain(name: "launchAgents", availability: viewModel.launchAgentAvailability,
                   coverage: latestCoverage?.launchAgents, unavailableSources: [],
                   itemCount: viewModel.launchAgents.count),
        ]
        self.lastScanDate = viewModel.lastScanDate
        self.latestSnapshotID = viewModel.latestSnapshotID
        self.latestSnapshotDate = viewModel.latestSnapshotDate
        self.schemaVersion = schemaVersion
        self.storeProblem = viewModel.snapshotStoreProblem
        self.digestEnabled = preferences.digestEnabled
        self.changeAlertsEnabled = preferences.changeAlertsEnabled
        self.notificationAuthorization = notificationAuthorization
        self.launchAtLogin = launchAtLogin
    }

    public var text: String {
        var lines = [
            "Permission Pulse diagnostics",
            "app: \(appVersion.identifier)",
            "bundlePath: \(bundlePath)",
            "translocated: \(isTranslocated)",
            "macOS: \(osVersion)",
            "architecture: \(architecture)",
        ]
        lines += domains.map(Self.line(for:))
        lines += [
            "lastScan: \(Self.format(lastScanDate))",
            "latestSnapshot: \(latestSnapshotID.map { String($0.rawValue) } ?? "none") at \(Self.format(latestSnapshotDate))",
            "schemaVersion: \(schemaVersion.map(String.init) ?? "unknown")",
            "historyStoreProblem: \(storeProblem.map { String(describing: $0) } ?? "none")",
            "weeklyDigest: \(digestEnabled ? "on" : "off")",
            "changeAlerts: \(changeAlertsEnabled ? "on" : "off")",
            "notificationAuthorization: \(notificationAuthorization)",
            "launchAtLogin: \(launchAtLogin)",
        ]
        return lines.joined(separator: "\n")
    }

    private static func line(for domain: Domain) -> String {
        let sources = domain.unavailableSources.map { String(describing: $0) }.joined(separator: ",")
        return "\(domain.name): availability=\(availabilityText(domain.availability))"
            + " coverage=\(domain.coverage?.rawValue ?? "none")"
            + " error=\(errorKind(domain.availability.error))"
            + " unavailableSources=[\(sources)]"
            + " items=\(domain.itemCount)"
    }

    private static func availabilityText(_ availability: ScanAvailability) -> String {
        switch availability {
        case .never: "never"
        case .complete: "complete"
        case .degraded(_, let warnings):
            "degraded(" + warnings.map { "\($0.source):\($0.omittedCount.map(String.init) ?? "?")" }
                .joined(separator: ",") + ")"
        case .failed: "failed"
        }
    }

    private static func errorKind(_ error: ScannerError?) -> String {
        switch error {
        case nil: "none"
        case .permissionDenied: "permissionDenied"
        case .schemaMismatch: "schemaMismatch"
        case .unsupportedOnThisOS: "unsupportedOnThisOS"
        case .temporarilyUnavailable: "temporarilyUnavailable"
        }
    }

    private static func format(_ date: Date?) -> String {
        date.map { $0.formatted(.iso8601) } ?? "never"
    }
}
