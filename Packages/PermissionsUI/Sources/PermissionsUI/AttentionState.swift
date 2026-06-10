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

    public static func evaluate(
        tccError: ScannerError?,
        btmError: ScannerError?,
        launchAgentError: ScannerError?
    ) -> AttentionState {
        if isPermissionDenied(tccError) { return .fdaDenied }
        if isPermissionDenied(btmError) { return .btmOnlyFDADenied }
        if isSchemaIssue(tccError) || isSchemaIssue(btmError) { return .schemaMismatch }
        if launchAgentError != nil { return .launchAgentError }
        return .clean
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
