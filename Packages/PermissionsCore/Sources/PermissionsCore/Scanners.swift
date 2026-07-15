import Foundation

public enum ScannerError: Error, Sendable, Equatable {
    case permissionDenied(reason: String)
    case schemaMismatch(detail: String)
    case unsupportedOnThisOS(detail: String)
    case temporarilyUnavailable(reason: String)
}

public enum ScannerSource: Sendable, Equatable {
    case userTCCDatabase
    case systemTCCDatabase
    case userLaunchAgents
    case libraryLaunchAgents
    case libraryLaunchDaemons
    case entries
}

public struct ScannerWarning: Sendable, Equatable {
    public let source: ScannerSource
    public let omittedCount: Int?

    public init(source: ScannerSource, omittedCount: Int? = nil) {
        self.source = source
        self.omittedCount = omittedCount
    }
}

public struct ScannerOutput<Item: Sendable>: Sendable {
    public let items: [Item]
    public let warnings: [ScannerWarning]

    public init(items: [Item], warnings: [ScannerWarning] = []) {
        self.items = items
        self.warnings = warnings
    }
}

extension ScannerOutput: Equatable where Item: Equatable {}

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
    func scan() async throws -> ScannerOutput<PermissionGrant>
}

public protocol LaunchAgentScanner: Sendable {
    func scan() async throws -> ScannerOutput<LaunchAgentItem>
}

public protocol BTMScanner: Sendable {
    func scan() async throws -> ScannerOutput<BTMItem>
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
