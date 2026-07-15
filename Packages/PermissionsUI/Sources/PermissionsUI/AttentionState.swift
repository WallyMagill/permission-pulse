import PermissionsCore

/// App-wide "does something need the user's attention" state, shared by the
/// dropdown, Overview page, and menu-bar icon copy. Extracted verbatim from
/// MenuBarContentView's private enum so the precedence is defined once.
public enum AttentionState: Equatable, Sendable {
    case clean
    case fdaDenied
    case btmOnlyFDADenied
    case schemaMismatch
    case launchAgentError
    case scanFailed
    case degradedData
    case staleData

    public static func evaluate(
        tccAvailability: ScanAvailability,
        btmAvailability: ScanAvailability,
        launchAgentAvailability: ScanAvailability
    ) -> AttentionState {
        let tccError = tccAvailability.error
        let btmError = btmAvailability.error
        let launchAgentError = launchAgentAvailability.error
        if isPermissionDenied(tccError) { return .fdaDenied }
        if isPermissionDenied(btmError) { return .btmOnlyFDADenied }
        if isSchemaIssue(tccError) || isSchemaIssue(btmError) || isSchemaIssue(launchAgentError) {
            return .schemaMismatch
        }
        if isFailed(launchAgentAvailability) { return .launchAgentError }
        if isFailedWithoutHistory(tccAvailability) || isFailedWithoutHistory(btmAvailability) {
            return .scanFailed
        }
        if isFailed(tccAvailability) || isFailed(btmAvailability) { return .staleData }
        if isDegraded(tccAvailability) || isDegraded(btmAvailability)
            || isDegraded(launchAgentAvailability) {
            return .degradedData
        }
        return .clean
    }

    private static func isFailed(_ availability: ScanAvailability) -> Bool {
        if case .failed = availability { true } else { false }
    }

    private static func isFailedWithoutHistory(_ availability: ScanAvailability) -> Bool {
        if case .failed(lastSuccessful: nil, error: _) = availability { true } else { false }
    }

    private static func isDegraded(_ availability: ScanAvailability) -> Bool {
        if case .degraded = availability { true } else { false }
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
