import Foundation

// Codable export representation, decoupled from the GRDB-backed domain models.
// Each DTO is plain String/Int/Bool/Date so JSON synthesis is automatic and the
// BTM associated-value enums collapse to stable strings. (F1)

public struct ExportReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let grants: [ExportGrant]
    public let launchAgents: [ExportLaunchAgent]
    public let backgroundItems: [ExportBackgroundItem]
    public let staleApps: [ExportStaleApp]
}

public struct ExportGrant: Codable, Sendable, Equatable {
    public let service: String
    public let serviceKey: String
    public let appName: String
    public let bundleID: String
    public let bundlePath: String?
    public let lastModified: Date
    public let automationTarget: String?
}

public struct ExportLaunchAgent: Codable, Sendable, Equatable {
    public let label: String
    public let source: String
    public let programPath: String?
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let isDisabled: Bool
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
    public static func report(
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        staleApps: [StaleApp],
        generatedAt: Date
    ) -> ExportReport {
        ExportReport(
            generatedAt: generatedAt,
            grants: grants.map(Self.map),
            launchAgents: launchAgents.map(Self.map),
            backgroundItems: btmItems.map(Self.map),
            staleApps: staleApps.map(Self.map)
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

        out += "## Permissions\n\n"
        if report.grants.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| App | Bundle ID | Service | Last modified |\n|---|---|---|---|\n"
            for g in report.grants {
                out += "| \(Self.cell(g.appName)) | \(Self.cell(g.bundleID)) | \(Self.cell(g.service)) | \(Self.iso(g.lastModified)) |\n"
            }
            out += "\n"
        }

        out += "## Launch Agents\n\n"
        if report.launchAgents.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| Label | Source | runAtLoad | keepAlive |\n|---|---|---|---|\n"
            for a in report.launchAgents {
                out += "| \(Self.cell(a.label)) | \(Self.cell(a.source)) | \(a.runAtLoad) | \(a.keepAlive) |\n"
            }
            out += "\n"
        }

        out += "## Background Items\n\n"
        if report.backgroundItems.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| Name | Developer | Type | Disposition |\n|---|---|---|---|\n"
            for b in report.backgroundItems {
                out += "| \(Self.cell(b.name)) | \(Self.cell(b.developerName ?? "—")) | \(b.type) | \(b.disposition) |\n"
            }
            out += "\n"
        }

        out += "## Stale Apps\n\n"
        if report.staleApps.isEmpty {
            out += "_None._\n\n"
        } else {
            out += "| App | Last used | Days | Services |\n|---|---|---|---|\n"
            for s in report.staleApps {
                out += "| \(Self.cell(s.appName)) | \(Self.iso(s.lastUsedDate)) | \(s.daysSinceUsed) | \(Self.cell(s.grantedServices.joined(separator: ", "))) |\n"
            }
            out += "\n"
        }
        return out
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
            automationTarget: g.automationTarget
        )
    }

    private static func map(_ a: LaunchAgentItem) -> ExportLaunchAgent {
        ExportLaunchAgent(
            label: a.label,
            source: a.sourceDirectory.rawValue,
            programPath: a.programPath,
            runAtLoad: a.runAtLoad,
            keepAlive: a.keepAlive,
            isDisabled: a.isDisabled
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
        switch type {
        case .app: "app"
        case .legacyDaemon: "legacyDaemon"
        case .developerGroup: "developerGroup"
        case .unknown(let raw): "unknown(\(raw))"
        }
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
        // A fresh formatter per call keeps this concurrency-safe (ISO8601DateFormatter
        // isn't Sendable); export is a one-shot action, so the cost is negligible.
        ISO8601DateFormatter().string(from: date)
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
