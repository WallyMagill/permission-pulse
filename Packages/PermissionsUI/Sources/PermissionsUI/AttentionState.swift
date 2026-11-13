import PermissionsCore

/// A section an attention row can point at: a scanned domain, or the
/// snapshot history Recent Changes reads.
public enum AttentionDomain: Sendable, Hashable, CaseIterable {
    case permissions
    case launchAgents
    case backgroundItems
    case history

    public var displayName: String {
        switch self {
        case .permissions: String(localized: "Permissions")
        case .launchAgents: String(localized: "Launch Agents")
        case .backgroundItems: String(localized: "Background Items")
        case .history: String(localized: "History")
        }
    }

    public var route: AppRoute {
        switch self {
        case .permissions: .permissions(selectAppKey: nil)
        case .launchAgents: .launchAgents(selectID: nil)
        case .backgroundItems: .backgroundItems(selectID: nil)
        case .history: .recentChanges
        }
    }
}

/// One section that needs attention, with that section's own most severe
/// state. Every affected section gets one, so a lesser problem in one
/// section is never hidden behind a worse one elsewhere.
public struct AttentionItem: Equatable, Sendable {
    public let state: AttentionState
    public let domain: AttentionDomain

    public init(state: AttentionState, domain: AttentionDomain) {
        self.state = state
        self.domain = domain
    }
}

/// App-wide "does something need the user's attention" state, shared by the
/// dropdown, Overview page, and menu-bar icon copy. `evaluate` gives the most
/// severe problem overall, carrying every domain that has it; `items` gives
/// one entry per affected section.
public enum AttentionState: Equatable, Sendable {
    case clean
    case fdaDenied
    case btmOnlyFDADenied
    case schemaMismatch([AttentionDomain])
    case launchAgentError
    case scanFailed([AttentionDomain])
    case degradedData([AttentionDomain])
    case staleData([AttentionDomain])
    /// The history database is unavailable or the last snapshot write failed.
    case historyNotRecorded

    /// The domains this state's rows route to, in display order.
    public var domains: [AttentionDomain] {
        switch self {
        case .clean: []
        case .fdaDenied: [.permissions]
        case .btmOnlyFDADenied: [.backgroundItems]
        case .launchAgentError: [.launchAgents]
        case .historyNotRecorded: [.history]
        case .schemaMismatch(let domains), .scanFailed(let domains),
             .degradedData(let domains), .staleData(let domains):
            domains
        }
    }

    /// One item per domain this state names.
    public var items: [AttentionItem] {
        domains.map { AttentionItem(state: self, domain: $0) }
    }

    public static func evaluate(
        tccAvailability: ScanAvailability,
        btmAvailability: ScanAvailability,
        launchAgentAvailability: ScanAvailability,
        historyNotRecorded: Bool = false
    ) -> AttentionState {
        let all = items(
            tccAvailability: tccAvailability,
            btmAvailability: btmAvailability,
            launchAgentAvailability: launchAgentAvailability,
            historyNotRecorded: historyNotRecorded
        )
        guard let worst = all.first?.state else { return .clean }
        let domains = all.filter { $0.state.severity == worst.severity }.map(\.domain)
        return worst.withDomains(domains)
    }

    /// Most severe first; sections with equal severity keep display order.
    public static func items(
        tccAvailability: ScanAvailability,
        btmAvailability: ScanAvailability,
        launchAgentAvailability: ScanAvailability,
        historyNotRecorded: Bool = false
    ) -> [AttentionItem] {
        let sections: [(AttentionDomain, AttentionState?)] = [
            (.permissions, scannedState(tccAvailability, domain: .permissions)),
            (.launchAgents, scannedState(launchAgentAvailability, domain: .launchAgents)),
            (.backgroundItems, scannedState(btmAvailability, domain: .backgroundItems)),
            (.history, historyNotRecorded ? .historyNotRecorded : nil),
        ]
        let found = sections.compactMap { domain, state in
            state.map { AttentionItem(state: $0, domain: domain) }
        }
        return found.enumerated()
            .sorted { ($0.element.state.severity, $0.offset) < ($1.element.state.severity, $1.offset) }
            .map(\.element)
    }

    private static func scannedState(_ availability: ScanAvailability, domain: AttentionDomain) -> AttentionState? {
        if isPermissionDenied(availability.error) {
            if domain == .permissions { return .fdaDenied }
            if domain == .backgroundItems { return .btmOnlyFDADenied }
        }
        if isSchemaIssue(availability.error) { return .schemaMismatch([domain]) }
        if case .failed(let lastSuccessful, _) = availability {
            if domain == .launchAgents { return .launchAgentError }
            return lastSuccessful == nil ? .scanFailed([domain]) : .staleData([domain])
        }
        if availability.hasActionableWarnings { return .degradedData([domain]) }
        return nil
    }

    /// Lower is more severe.
    var severity: Int {
        switch self {
        case .fdaDenied: 0
        case .btmOnlyFDADenied: 1
        case .schemaMismatch: 2
        case .launchAgentError: 3
        case .scanFailed: 4
        case .staleData: 5
        case .historyNotRecorded: 6
        case .degradedData: 7
        case .clean: 8
        }
    }

    private func withDomains(_ domains: [AttentionDomain]) -> AttentionState {
        switch self {
        case .schemaMismatch: .schemaMismatch(domains)
        case .scanFailed: .scanFailed(domains)
        case .staleData: .staleData(domains)
        case .degradedData: .degradedData(domains)
        case .clean, .fdaDenied, .btmOnlyFDADenied, .launchAgentError, .historyNotRecorded: self
        }
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
