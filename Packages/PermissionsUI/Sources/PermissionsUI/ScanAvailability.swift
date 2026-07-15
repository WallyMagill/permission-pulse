import Foundation
import PermissionsCore

public enum ScanAvailability: Sendable, Equatable {
    case never
    case complete(lastUpdated: Date)
    case degraded(lastUpdated: Date, warnings: [ScannerWarning])
    case failed(lastSuccessful: Date?, error: ScannerError)

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    public var lastSuccessful: Date? {
        switch self {
        case .never: nil
        case .complete(let lastUpdated), .degraded(let lastUpdated, _): lastUpdated
        case .failed(let lastSuccessful, _): lastSuccessful
        }
    }

    public var error: ScannerError? {
        if case .failed(_, let error) = self { return error }
        return nil
    }
}
