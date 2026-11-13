import Foundation
import PermissionsCore
import PermissionsStore

/// The snapshot one domain was compared against.
public struct DiffBaseline: Sendable, Equatable {
    public let id: SnapshotID
    public let date: Date

    public init(id: SnapshotID, date: Date) {
        self.id = id
        self.date = date
    }
}

/// Changes from each domain's baseline to the latest snapshot. Each domain
/// picks its own baseline, so one incomplete snapshot never blocks the
/// others.
public struct SnapshotDiffs: Sendable, Equatable {
    public let toID: SnapshotID
    public let tcc: TCCGrantsDiff
    public let btm: BTMItemsDiff
    public let launchAgents: LaunchAgentsDiff
    /// The baseline of every compared domain.
    public let baselines: [HistoryDomain: DiffBaseline]
    /// Domains not compared, and why; their diffs are empty rather than built
    /// from partial evidence.
    public let uncompared: [HistoryDomain: UncomparedReason]
    /// Permissions were compared across the macOS 27 boundary, so only the
    /// system-level services the later scan can see were diffed.
    public let systemLevelPermissionsOnly: Bool
    /// Set when the window is anchored to the snapshot the user last
    /// reviewed rather than a calendar cutoff.
    public let reviewedSnapshotID: SnapshotID?

    public init(
        toID: SnapshotID,
        tcc: TCCGrantsDiff,
        btm: BTMItemsDiff,
        launchAgents: LaunchAgentsDiff,
        baselines: [HistoryDomain: DiffBaseline] = [:],
        uncompared: [HistoryDomain: UncomparedReason] = [:],
        systemLevelPermissionsOnly: Bool = false,
        reviewedSnapshotID: SnapshotID? = nil
    ) {
        self.toID = toID
        self.tcc = tcc
        self.btm = btm
        self.launchAgents = launchAgents
        self.baselines = baselines
        self.uncompared = uncompared
        self.systemLevelPermissionsOnly = systemLevelPermissionsOnly
        self.reviewedSnapshotID = reviewedSnapshotID
    }

    public var hasContent: Bool {
        tcc.hasContent || btm.hasContent || launchAgents.hasContent
    }

    public var uncomparedDomains: [HistoryDomain] {
        HistoryDomain.allCases.filter { uncompared[$0] != nil }
    }

    public var comparedDomains: [HistoryDomain] {
        HistoryDomain.allCases.filter { uncompared[$0] == nil }
    }
}
