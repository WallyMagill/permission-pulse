import Foundation
import PermissionsStore

/// The three domains snapshot history records. Distinct from `ScannerDomain`,
/// which only covers the FDA-gated scanners.
public enum HistoryDomain: String, Sendable, CaseIterable {
    case tcc
    case btm
    case launchAgents

    public var displayName: String {
        switch self {
        case .tcc: String(localized: "Permissions")
        case .btm: String(localized: "Background Items")
        case .launchAgents: String(localized: "Launch Agents")
        }
    }

    public var coverage: KeyPath<SnapshotDomainCoverage, SnapshotCoverage> {
        switch self {
        case .tcc: \.tcc
        case .btm: \.btm
        case .launchAgents: \.launchAgents
        }
    }
}

/// The two Recent Changes windows.
public enum RecentChangesWindow: Sendable, Hashable {
    /// Since the snapshot the user last reviewed (start of today when none).
    case sinceLastReview
    case lastSevenDays
}

/// Why the history database could not be opened.
public enum SnapshotStoreProblem: Sendable, Equatable {
    case createdByNewerVersion
    case corrupt
    case unavailable
}
