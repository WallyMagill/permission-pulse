import Foundation
import PermissionsCore

/// A stored snapshot's identity, time and per-domain coverage.
public struct SnapshotSummary: Sendable, Equatable {
    public let id: SnapshotID
    public let date: Date
    public let coverage: SnapshotDomainCoverage

    public init(id: SnapshotID, date: Date, coverage: SnapshotDomainCoverage) {
        self.id = id
        self.date = date
        self.coverage = coverage
    }
}

/// Why a domain has no usable baseline in a window.
public enum UncomparedReason: Sendable, Equatable {
    /// Earlier snapshots captured a full scope, but a different one: macOS
    /// changed what is readable.
    case scopeChanged
    /// The latest scan stored nothing for the domain.
    case latestScanFailed
    /// An endpoint captured only part of the domain.
    case itemsUnreadable
    /// No snapshot at or before the cutoff recorded the domain.
    case noEarlierSnapshot
}

public enum BaselineChoice: Sendable, Equatable {
    case compared(SnapshotSummary, systemLevelOnly: Bool)
    case notCompared(UncomparedReason)
}

public enum BaselineSelector {
    /// Picks one domain's baseline: the newest candidate whose coverage can
    /// be compared with the latest snapshot's. `candidates` are the snapshots
    /// at or before the window's cutoff, newest first.
    public static func choose(
        latest: SnapshotCoverage,
        candidates: [SnapshotSummary],
        domain: KeyPath<SnapshotDomainCoverage, SnapshotCoverage>
    ) -> BaselineChoice {
        switch latest {
        case .failed: return .notCompared(.latestScanFailed)
        case .degraded: return .notCompared(.itemsUnreadable)
        case .complete, .reduced: break
        }
        let captured = candidates.filter { $0.coverage[keyPath: domain] != .failed }
        if let baseline = captured.first(where: { $0.coverage[keyPath: domain].canBaseline(latest) }) {
            let narrowed = baseline.coverage[keyPath: domain].canNarrow(to: latest)
            return .compared(baseline, systemLevelOnly: narrowed)
        }
        if captured.isEmpty { return .notCompared(.noEarlierSnapshot) }
        if captured.contains(where: { $0.coverage[keyPath: domain].capturedFullScope }) {
            return .notCompared(.scopeChanged)
        }
        return .notCompared(.itemsUnreadable)
    }

    /// The snapshots at or before a cutoff that any future latest snapshot
    /// could still pick as a baseline: per domain, the newest one of each
    /// full scope. `candidates` are newest first.
    static func retainedBaselines(among candidates: [SnapshotSummary]) -> Set<SnapshotID> {
        let domains: [KeyPath<SnapshotDomainCoverage, SnapshotCoverage>] = [\.tcc, \.btm, \.launchAgents]
        var kept = Set<SnapshotID>()
        for domain in domains {
            for scope in [SnapshotCoverage.complete, .reduced] {
                if let newest = candidates.first(where: { $0.coverage[keyPath: domain] == scope }) {
                    kept.insert(newest.id)
                }
            }
        }
        return kept
    }
}
