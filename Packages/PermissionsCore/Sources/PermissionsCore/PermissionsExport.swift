import Foundation

// Codable export representation, decoupled from the GRDB-backed domain models.
// Each DTO is plain String/Int/Bool/Date so JSON synthesis is automatic and the
// BTM associated-value enums collapse to stable strings. (F1)

public struct ExportReport: Codable, Sendable, Equatable {
    /// The export format's version. 2 added the environment, coverage and
    /// grant `authValue`; 3 added `staleAppsStatus` and writes null for
    /// launch agent details that could not be read. Earlier exports carried
    /// no version.
    public let schemaVersion: Int
    public let generatedAt: Date
    public let appVersion: String
    public let appBuild: String
    public let macOSVersion: String
    public let coverage: ExportCoverage
    public let grants: [ExportGrant]
    public let launchAgents: [ExportLaunchAgent]
    public let backgroundItems: [ExportBackgroundItem]
    public let staleApps: [ExportStaleApp]
    public let staleAppsStatus: ExportStaleAppsStatus
}

/// Whether Stale Apps was computed, so an empty list says whether nothing
/// was stale or nothing was checked.
public enum ExportStaleAppsStatus: String, Codable, Sendable {
    case checked
    case permissionsNotScanned
    case historyUnavailable
}

public struct ExportGrant: Codable, Sendable, Equatable {
    public let service: String
    public let serviceKey: String
    public let appName: String
    public let bundleID: String
    public let bundlePath: String?
    public let lastModified: Date
    public let automationTarget: String?
    /// TCC auth_value: 2 = allowed, 3 = limited.
    public let authValue: Int
}

public struct ExportLaunchAgent: Codable, Sendable, Equatable {
    public let label: String
    public let source: String
    public let programPath: String?
    /// Null when the plist could not be read: unknown, not false.
    public let runAtLoad: Bool?
    public let keepAlive: Bool?
    public let isDisabled: Bool
    public let detailsReadable: Bool
    public let fileName: String?

    private enum CodingKeys: String, CodingKey {
        case label, source, programPath, runAtLoad, keepAlive, isDisabled, detailsReadable, fileName
    }

    /// Writes unknown values as explicit nulls; the synthesized encoder
    /// would drop the keys.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(programPath, forKey: .programPath)
        try container.encode(runAtLoad, forKey: .runAtLoad)
        try container.encode(keepAlive, forKey: .keepAlive)
        try container.encode(isDisabled, forKey: .isDisabled)
        try container.encode(detailsReadable, forKey: .detailsReadable)
        try container.encodeIfPresent(fileName, forKey: .fileName)
    }
}

public struct ExportBackgroundItem: Codable, Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let developerName: String?
    public let bundleIdentifier: String?
    public let type: String
    public let disposition: String
    public let scope: String
    public let modificationDate: Date
}

public struct ExportStaleApp: Codable, Sendable, Equatable {
    public let appName: String
    public let bundleID: String
    public let lastUsedDate: Date
    public let dateSource: String
    public let daysSinceUsed: Int
    public let grantedServices: [String]
}

public enum PermissionsExport {
    public static let schemaVersion = 3

    public static func report(
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        staleApps: [StaleApp],
        generatedAt: Date,
        environment: ExportEnvironment,
        coverage: ExportCoverage,
        staleAppsStatus: ExportStaleAppsStatus = .checked
    ) -> ExportReport {
        ExportReport(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            appVersion: environment.appVersion,
            appBuild: environment.appBuild,
            macOSVersion: environment.macOSVersion,
            coverage: coverage,
            grants: grants.map(Self.map),
            launchAgents: launchAgents.map(Self.map),
            backgroundItems: btmItems.map(Self.map),
            staleApps: staleApps.map(Self.map),
            staleAppsStatus: staleAppsStatus
        )
    }

    public static func makeJSON(report: ExportReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    // The Markdown scaffold (headings, table columns, preamble) is intentionally
    // English and NOT routed through String(localized:): it is the export's stable
    // schema — a machine-readable artifact users share/diff — not in-app prose.
    public static func makeMarkdown(report: ExportReport) -> String {
        var out = "# Permission Pulse export\n\n"
        out += "_Generated \(Self.iso(report.generatedAt)) · read-only snapshot of current state._\n\n"
        out += coverageBlock(report)
        let coverage = report.coverage
        out += section("Permissions", coverage: coverage.permissions, rows: report.grants.map(Self.row),
                       header: "| App | Bundle ID | Service | Last modified |")
        out += section("Launch Agents", coverage: coverage.launchAgents, rows: report.launchAgents.map(Self.row),
                       header: "| Label | Source | runAtLoad | keepAlive |")
        out += section("Background Items", coverage: coverage.backgroundItems,
                       rows: report.backgroundItems.map(Self.row),
                       header: "| Name | Developer | Type | Disposition |")
        out += staleAppsSection(report)
        return out
    }

    /// Says why Stale Apps was not checked instead of printing "None".
    private static func staleAppsSection(_ report: ExportReport) -> String {
        var out = "## Stale Apps\n\n"
        if !report.coverage.permissions.hasData || report.staleAppsStatus == .permissionsNotScanned {
            return out + "_Not checked: permissions were not scanned._\n\n"
        }
        if report.staleAppsStatus == .historyUnavailable {
            return out + "_Not checked: Permission Pulse's local history isn't available._\n\n"
        }
        if report.coverage.permissions.coverage == .reduced {
            out += "_Checks apps with system-level permissions only._\n\n"
        }
        return out + table(header: "| App | Last used | Days | Services |", rows: report.staleApps.map(Self.row))
    }

    private static func coverageBlock(_ report: ExportReport) -> String {
        let lines = [
            "- Permission Pulse \(report.appVersion) (\(report.appBuild)) on macOS \(report.macOSVersion). Export format \(report.schemaVersion).",
            report.coverage.permissions.coverageLine(name: "Permissions"),
            report.coverage.launchAgents.coverageLine(name: "Launch Agents"),
            report.coverage.backgroundItems.coverageLine(name: "Background Items"),
        ]
        return "## Scan coverage\n\n" + lines.joined(separator: "\n") + "\n\n"
    }

    /// A domain that was never read prints only why; otherwise its note
    /// (if the scan was not complete) and its table.
    private static func section(
        _ title: String,
        coverage: ExportDomainCoverage,
        rows: [String],
        header: String
    ) -> String {
        var out = "## \(title)\n\n"
        if let note = coverage.markdownNote { out += note + "\n\n" }
        guard coverage.hasData else { return out }
        return out + table(header: header, rows: rows)
    }

    private static func table(header: String, rows: [String]) -> String {
        guard !rows.isEmpty else { return "_None._\n\n" }
        return header + "\n|---|---|---|---|\n" + rows.joined(separator: "\n") + "\n\n"
    }

    private static func row(_ g: ExportGrant) -> String {
        "| \(cell(g.appName)) | \(cell(g.bundleID)) | \(cell(g.service)) | \(iso(g.lastModified)) |"
    }

    private static func row(_ a: ExportLaunchAgent) -> String {
        "| \(cell(a.label)) | \(cell(a.source)) | \(a.runAtLoad.map(String.init) ?? "unknown") | \(a.keepAlive.map(String.init) ?? "unknown") |"
    }

    private static func row(_ b: ExportBackgroundItem) -> String {
        "| \(cell(b.name)) | \(cell(b.developerName ?? "—")) | \(b.type) | \(b.disposition) |"
    }

    private static func row(_ s: ExportStaleApp) -> String {
        "| \(cell(s.appName)) | \(iso(s.lastUsedDate)) | \(s.daysSinceUsed) | \(cell(s.grantedServices.joined(separator: ", "))) |"
    }

    // MARK: - Mapping

    private static func map(_ g: PermissionGrant) -> ExportGrant {
        ExportGrant(
            service: g.service.displayName,
            serviceKey: g.service.rawValue,
            appName: g.app.displayName,
            bundleID: g.app.bundleID,
            bundlePath: g.app.bundlePath?.path(percentEncoded: false),
            lastModified: g.lastModified,
            automationTarget: g.automationTarget,
            authValue: g.authValue
        )
    }

    private static func map(_ a: LaunchAgentItem) -> ExportLaunchAgent {
        ExportLaunchAgent(
            label: a.label,
            source: a.sourceDirectory.rawValue,
            programPath: a.programPath,
            runAtLoad: a.detailsReadable ? a.runAtLoad : nil,
            keepAlive: a.detailsReadable ? a.keepAlive : nil,
            isDisabled: a.isDisabled,
            detailsReadable: a.detailsReadable,
            fileName: a.fileName
        )
    }

    private static func map(_ b: BTMItem) -> ExportBackgroundItem {
        ExportBackgroundItem(
            identifier: b.identifier,
            name: b.name,
            developerName: b.developerName,
            bundleIdentifier: b.bundleIdentifier,
            type: Self.string(for: b.type),
            disposition: Self.string(for: b.disposition),
            scope: Self.string(for: b.scope),
            modificationDate: b.modificationDate
        )
    }

    private static func map(_ s: StaleApp) -> ExportStaleApp {
        ExportStaleApp(
            appName: s.app.displayName,
            bundleID: s.app.bundleID,
            lastUsedDate: s.lastUsedDate,
            dateSource: s.dateSource == .spotlight ? "spotlight" : "fileSystem",
            daysSinceUsed: s.daysSinceUsed,
            grantedServices: s.grantedServices.map(\.rawValue)
        )
    }

    private static func string(for type: BTMItem.ItemType) -> String {
        if case .unknown(let raw) = type { return "unknown(\(raw))" }
        return type.kindName
    }

    private static func string(for disposition: BTMItem.Disposition) -> String {
        switch disposition {
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .unknown(let raw): "unknown(\(raw))"
        }
    }

    private static func string(for scope: BTMItem.Scope) -> String {
        switch scope {
        case .system: "system"
        case .user: "user"
        case .perUser(let uuid): "perUser(\(uuid))"
        }
    }

    private static func iso(_ date: Date) -> String {
        ExportFormat.iso(date)
    }

    /// Escapes a value for a Markdown table cell: pipes break columns and
    /// newlines break the table, so neutralize both. App-controlled strings
    /// (names, labels, bundle IDs) flow through here.
    private static func cell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
