import Foundation

public enum ScannerError: Error, Sendable {
    case permissionDenied(reason: String)
    case schemaMismatch(detail: String)
    case unsupportedOnThisOS(detail: String)
}

extension ScannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let reason):    reason
        case .schemaMismatch(let detail):      detail
        case .unsupportedOnThisOS(let detail): detail
        }
    }
}

public protocol TCCScanner: Sendable {
    func scan() async throws -> [PermissionGrant]
}

public protocol LaunchAgentScanner: Sendable {
    func scan() async throws -> [LaunchAgentItem]
}
