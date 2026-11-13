import Foundation

/// What one domain's scan covered when the export was made, so an export
/// with an empty section says whether nothing was there or nothing was read.
public struct ExportDomainCoverage: Codable, Sendable, Equatable {
    public enum Level: String, Codable, Sendable {
        case complete
        /// Complete within what macOS lets apps see (macOS 27 per-user records hidden).
        case reduced
        case degraded
        case failed
    }

    public enum FailureReason: String, Codable, Sendable {
        case fullDiskAccessOff
        case unrecognizedFormat
        case sourceUnavailable
        case notScannedYet
    }

    public let coverage: Level
    public let lastSuccessfulScan: Date?
    /// `PermissionService` raw values macOS hides from apps; empty when none.
    public let unavailableServices: [String]
    public let failureReason: FailureReason?

    public init(
        coverage: Level,
        lastSuccessfulScan: Date?,
        unavailableServices: [String] = [],
        failureReason: FailureReason? = nil
    ) {
        self.coverage = coverage
        self.lastSuccessfulScan = lastSuccessfulScan
        self.unavailableServices = unavailableServices
        self.failureReason = failureReason
    }

    /// False when the domain has never been read: its item list means nothing.
    public var hasData: Bool {
        coverage != .failed || lastSuccessfulScan != nil
    }
}

public struct ExportCoverage: Codable, Sendable, Equatable {
    public let permissions: ExportDomainCoverage
    public let launchAgents: ExportDomainCoverage
    public let backgroundItems: ExportDomainCoverage

    public init(
        permissions: ExportDomainCoverage,
        launchAgents: ExportDomainCoverage,
        backgroundItems: ExportDomainCoverage
    ) {
        self.permissions = permissions
        self.launchAgents = launchAgents
        self.backgroundItems = backgroundItems
    }
}

/// The app and OS that produced an export.
public struct ExportEnvironment: Sendable, Equatable {
    public let appVersion: String
    public let appBuild: String
    public let macOSVersion: String

    public init(appVersion: String, appBuild: String, macOSVersion: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.macOSVersion = macOSVersion
    }
}

// The Markdown wording is English on purpose, like the rest of the export
// scaffold (see PermissionsExport.makeMarkdown).
extension ExportDomainCoverage {
    /// The line a Markdown section prints above (or instead of) its table.
    var markdownNote: String? {
        switch coverage {
        case .complete:
            return nil
        case .reduced:
            return "_System-level permissions only: this version of macOS hides per-user permissions from apps._"
        case .degraded:
            return "_Partial data: some sources or entries could not be read._"
        case .failed:
            if let lastSuccessfulScan {
                return "_Last-known data from \(ExportFormat.iso(lastSuccessfulScan))._"
            }
            if failureReason == .notScannedYet || failureReason == nil { return "_Not scanned yet._" }
            return "_Not scanned: \(reasonText)._"
        }
    }

    var reasonText: String {
        switch failureReason {
        case .fullDiskAccessOff: "Full Disk Access is off"
        case .unrecognizedFormat: "the data format was not recognized"
        case .sourceUnavailable: "the data source could not be read"
        case .notScannedYet, nil: "no scan has run yet"
        }
    }

    func coverageLine(name: String) -> String {
        var line = "- \(name): \(coverage.rawValue)"
        if coverage == .failed { line += " (\(reasonText))" }
        line += ". Last successful scan: \(lastSuccessfulScan.map(ExportFormat.iso) ?? "never")."
        if !unavailableServices.isEmpty {
            let names = unavailableServices.map { PermissionService(rawValue: $0)?.displayName ?? $0 }
            line += " Hidden by macOS: \(names.joined(separator: ", "))."
        }
        return line
    }
}

enum ExportFormat {
    static func iso(_ date: Date) -> String {
        // A fresh formatter per call keeps this concurrency-safe (ISO8601DateFormatter
        // isn't Sendable); export is a one-shot action, so the cost is negligible.
        ISO8601DateFormatter().string(from: date)
    }
}
