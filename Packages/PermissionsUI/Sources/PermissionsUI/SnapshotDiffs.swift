import Foundation
import PermissionsCore
import PermissionsStore

public struct SnapshotDiffs: Sendable, Equatable {
    public let fromID: SnapshotID
    public let toID: SnapshotID
    public let tcc: TCCGrantsDiff
    public let btm: BTMItemsDiff
    public let launchAgents: LaunchAgentsDiff

    public init(
        fromID: SnapshotID,
        toID: SnapshotID,
        tcc: TCCGrantsDiff,
        btm: BTMItemsDiff,
        launchAgents: LaunchAgentsDiff
    ) {
        self.fromID = fromID
        self.toID = toID
        self.tcc = tcc
        self.btm = btm
        self.launchAgents = launchAgents
    }

    public var hasContent: Bool {
        tcc.hasContent || btm.hasContent || launchAgents.hasContent
    }
}
