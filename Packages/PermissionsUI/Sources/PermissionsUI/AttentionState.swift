import PermissionsCore

/// A scanned domain an attention row can point at.
public enum AttentionDomain: Sendable, Hashable, CaseIterable {
    case permissions
    case launchAgents
    case backgroundItems

    public var displayName: String {
        switch self {
        case .permissions: String(localized: "Permissions")
        case .launchAgents: String(localized: "Launch Agents")
        case .backgroundItems: String(localized: "Background Items")
        }
    }

    public var route: AppRoute {
        switch self {
        case .permissions: .permissions(selectAppKey: nil)
        case .launchAgents: .launchAgents(selectID: nil)
        case .backgroundItems: .backgroundItems(selectID: nil)
        }
    }
}

/// App-wide "does something need the user's attention" state, shared by the
/// dropdown, Overview page, and menu-bar icon copy. The highest-precedence
/// problem wins; it carries every domain that has that problem so each one
/// gets its own row pointing at its own page.
public enum AttentionState: Equatable, Sendable {
    case clean
    case fdaDenied
    case btmOnlyFDADenied
    case schemaMismatch([AttentionDomain])
    case launchAgentError
    case scanFailed([AttentionDomain])
    case degradedData([AttentionDomain])
    case staleData([AttentionDomain])

    /// The domains this state's rows route to, in display order.
    public var domains: [AttentionDomain] {
        switch self {
        case .clean: []
        case .fdaDenied: [.permissions]
        case .btmOnlyFDADenied: [.backgroundItems]
        case .launchAgentError: [.launchAgents]
        case .schemaMismatch(let domains), .scanFailed(let domains),
             .degradedData(let domains), .staleData(let domains):
            domains
        }
    }

    public static func evaluate(
        tccAvailability: ScanAvailability,
        btmAvailability: ScanAvailability,
        launchAgentAvailability: ScanAvailability
    ) -> AttentionState {
        let all: [(domain: AttentionDomain, availability: ScanAvailability)] = [
            (.permissions, tccAvailability),
            (.launchAgents, launchAgentAvailability),
            (.backgroundItems, btmAvailability),
        ]
        let fdaGated = all.filter { $0.domain != .launchAgents }
        func domains(
            in list: [(domain: AttentionDomain, availability: ScanAvailability)],
            where test: (ScanAvailability) -> Bool
        ) -> [AttentionDomain] {
            list.filter { test($0.availability) }.map(\.domain)
        }

        if isPermissionDenied(tccAvailability.error) { return .fdaDenied }
        if isPermissionDenied(btmAvailability.error) { return .btmOnlyFDADenied }
        let schema = domains(in: all) { isSchemaIssue($0.error) }
        if !schema.isEmpty { return .schemaMismatch(schema) }
        if isFailed(launchAgentAvailability) { return .launchAgentError }
        let failed = domains(in: fdaGated) { isFailed($0) && $0.lastSuccessful == nil }
        if !failed.isEmpty { return .scanFailed(failed) }
        let stale = domains(in: fdaGated, where: isFailed)
        if !stale.isEmpty { return .staleData(stale) }
        let degraded = domains(in: all) { $0.hasActionableWarnings }
        if !degraded.isEmpty { return .degradedData(degraded) }
        return .clean
    }

    private static func isFailed(_ availability: ScanAvailability) -> Bool {
        if case .failed = availability { true } else { false }
    }

    private static func isPermissionDenied(_ error: ScannerError?) -> Bool {
        if case .permissionDenied = error { true } else { false }
    }

    private static func isSchemaIssue(_ error: ScannerError?) -> Bool {
        switch error {
        case .schemaMismatch, .unsupportedOnThisOS: true
        default: false
        }
    }
}
