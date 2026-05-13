import Foundation

public enum ScannerError: Error, Sendable {
    case permissionDenied(reason: String)
    case schemaMismatch(detail: String)
    case unsupportedOnThisOS(detail: String)
}

public protocol TCCScanner: Sendable {
    func scan() async throws -> [PermissionGrant]
}

public protocol LaunchAgentScanner: Sendable {
    func scan() async throws -> [LaunchAgentItem]
}
