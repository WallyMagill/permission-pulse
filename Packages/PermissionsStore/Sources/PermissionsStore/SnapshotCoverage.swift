import Foundation

/// How much of one domain a snapshot captured. A `.failed` domain stores no
/// rows.
public enum SnapshotCoverage: String, Sendable, Equatable {
    case complete
    /// Everything this macOS version exposes was captured, but that is less
    /// than `.complete` covers: macOS 27 hides the per-user TCC records.
    case reduced
    case degraded
    case failed

    /// Whether a diff between two snapshots with these coverages is sound.
    /// Both must have captured the same full scope; a `.complete` snapshot
    /// against a `.reduced` one would turn the hidden records into removals.
    public func isComparable(with other: SnapshotCoverage) -> Bool {
        self == other && (self == .complete || self == .reduced)
    }

    /// Whether "no rows changed" can be claimed for this domain.
    public var capturedFullScope: Bool {
        isComparable(with: self)
    }
}

public struct SnapshotDomainCoverage: Sendable, Equatable {
    public var tcc: SnapshotCoverage
    public var btm: SnapshotCoverage
    public var launchAgents: SnapshotCoverage

    public init(tcc: SnapshotCoverage, btm: SnapshotCoverage, launchAgents: SnapshotCoverage) {
        self.tcc = tcc
        self.btm = btm
        self.launchAgents = launchAgents
    }

    public static let allComplete = SnapshotDomainCoverage(
        tcc: .complete,
        btm: .complete,
        launchAgents: .complete
    )
}
