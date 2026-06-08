import Foundation

public enum ScannerError: Error, Sendable {
    case permissionDenied(reason: String)
    case schemaMismatch(detail: String)
    case unsupportedOnThisOS(detail: String)
    case temporarilyUnavailable(reason: String)
}

extension ScannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let reason):       reason
        case .schemaMismatch(let detail):         detail
        case .unsupportedOnThisOS(let detail):    detail
        case .temporarilyUnavailable(let reason): reason
        }
    }
}

public protocol TCCScanner: Sendable {
    func scan() async throws -> [PermissionGrant]
}

public protocol LaunchAgentScanner: Sendable {
    func scan() async throws -> [LaunchAgentItem]
}

public protocol BTMScanner: Sendable {
    func scan() async throws -> [BTMItem]
}

public struct MediaUseEvent: Sendable, Equatable {
    public enum Device: Sendable, Equatable {
        case microphone
        case camera
    }

    public let device: Device
    public let inUse: Bool
    public let timestamp: Date

    public init(device: Device, inUse: Bool, timestamp: Date) {
        self.device = device
        self.inUse = inUse
        self.timestamp = timestamp
    }
}

public protocol MediaUseObserver: Sendable {
    func events() -> AsyncStream<MediaUseEvent>
    func stop() async
}

public protocol LastUsedProbe: Sendable {
    func lastUsedDate(for bundlePath: URL) async -> (date: Date, source: StaleApp.DateSource)?
}
