import Foundation

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
}
