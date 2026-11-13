import Foundation
import PermissionsCore
import PermissionsStore

/// The snapshot-store calls `SnapshotCoordinator` makes. A protocol so tests
/// can hold one call open and interleave scans with refreshes.
@MainActor
protocol SnapshotHistoryStore: Sendable {
    func latestSnapshotID() async throws -> SnapshotID?
    func snapshotSummary(id: SnapshotID) async throws -> SnapshotSummary?
    func snapshotSummaries(atOrBefore cutoff: Date) async throws -> [SnapshotSummary]
    func evidenceChanged(
        since snapshotID: SnapshotID,
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        coverage: SnapshotDomainCoverage
    ) async throws -> Bool
    func writeSnapshot(
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        coverage: SnapshotDomainCoverage,
        at date: Date
    ) async throws -> SnapshotID
    func pruneSnapshots(olderThan cutoff: Date, keeping protected: Set<SnapshotID>) async throws -> Int
    func diffTCCGrants(
        from: SnapshotID,
        to: SnapshotID,
        limitedTo services: Set<PermissionService>?
    ) async throws -> TCCGrantsDiff
    func diffBTMItems(from: SnapshotID, to: SnapshotID) async throws -> BTMItemsDiff
    func diffLaunchAgents(from: SnapshotID, to: SnapshotID) async throws -> LaunchAgentsDiff
}

extension SnapshotStore: SnapshotHistoryStore {}
