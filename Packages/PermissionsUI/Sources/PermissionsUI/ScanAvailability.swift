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

    /// Degraded by something other than individual omitted entries. A
    /// warning that only says some entries were skipped is informational:
    /// every source was read.
    public var hasActionableWarnings: Bool {
        guard case .degraded(_, let warnings) = self else { return false }
        return warnings.contains { $0.source != .entries }
    }

    /// Degraded only because individual entries were omitted.
    public var onlyOmittedEntries: Bool {
        guard case .degraded(_, let warnings) = self else { return false }
        return !warnings.isEmpty && !hasActionableWarnings
    }
}
