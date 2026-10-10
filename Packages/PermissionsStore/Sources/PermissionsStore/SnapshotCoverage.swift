import Foundation

/// How much of one domain a snapshot captured. Diffs only compare a domain
/// when both endpoints are `.complete`; a `.failed` domain stores no rows.
public enum SnapshotCoverage: String, Sendable, Equatable {
    case complete
    case degraded
    case failed
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
