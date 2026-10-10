import Foundation
import PermissionsCore
import PermissionsStore

public struct SnapshotDiffs: Sendable, Equatable {
    public let fromID: SnapshotID
    public let toID: SnapshotID
    public let tcc: TCCGrantsDiff
    public let btm: BTMItemsDiff
    public let launchAgents: LaunchAgentsDiff
    /// Domains not compared because an endpoint snapshot was not complete for
    /// them; their diffs are empty rather than built from partial evidence.
    public let uncomparedDomains: [HistoryDomain]

    public init(
        fromID: SnapshotID,
        toID: SnapshotID,
        tcc: TCCGrantsDiff,
        btm: BTMItemsDiff,
        launchAgents: LaunchAgentsDiff,
        uncomparedDomains: [HistoryDomain] = []
    ) {
        self.fromID = fromID
        self.toID = toID
        self.tcc = tcc
        self.btm = btm
        self.launchAgents = launchAgents
        self.uncomparedDomains = uncomparedDomains
    }

    public var hasContent: Bool {
        tcc.hasContent || btm.hasContent || launchAgents.hasContent
    }
}
