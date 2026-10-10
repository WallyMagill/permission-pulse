import Foundation
import GRDB
import PermissionsCore

extension SnapshotStore {
    // MARK: - Snapshot diffs

    public func diffLaunchAgents(
        from: SnapshotID,
        to: SnapshotID
    ) async throws -> LaunchAgentsDiff {
        Self.diffLaunchAgents(
            before: try await readLaunchAgents(snapshotID: from),
            after: try await readLaunchAgents(snapshotID: to),
            compareDisabled: try await launchAgentDisabledCaptured(from: from, to: to)
        )
    }

    public func diffTCCGrants(
        from: SnapshotID,
        to: SnapshotID
    ) async throws -> TCCGrantsDiff {
        Self.diffTCCGrants(
            before: try await readTCCGrants(snapshotID: from),
            after: try await readTCCGrants(snapshotID: to)
        )
    }

    public func diffBTMItems(
        from: SnapshotID,
        to: SnapshotID
    ) async throws -> BTMItemsDiff {
        Self.diffBTMItems(
            before: try await readBTMItems(snapshotID: from),
            after: try await readBTMItems(snapshotID: to)
        )
    }

    // MARK: - Array diffs

    public static func diffLaunchAgents(
        before: [LaunchAgentItem],
        after: [LaunchAgentItem],
        compareDisabled: Bool
    ) -> LaunchAgentsDiff {
        computeDiff(
            before: before,
            after: after,
            identity: launchAgentIdentityKey,
            equivalent: { launchAgentsEquivalent($0, $1, compareDisabled: compareDisabled) },
            wrap: { LaunchAgentsDiff(added: $0, removed: $1, changed: $2) }
        )
    }

    public static func diffTCCGrants(
        before: [PermissionGrant],
        after: [PermissionGrant]
    ) -> TCCGrantsDiff {
        computeDiff(
            before: before,
            after: after,
            identity: tccGrantIdentityKey,
            equivalent: { $0 == $1 },
            wrap: { TCCGrantsDiff(added: $0, removed: $1, changed: $2) }
        )
    }

    public static func diffBTMItems(before: [BTMItem], after: [BTMItem]) -> BTMItemsDiff {
        computeDiff(
            before: before,
            after: after,
            identity: btmItemIdentityKey,
            equivalent: { $0 == $1 },
            wrap: { BTMItemsDiff(added: $0, removed: $1, changed: $2) }
        )
    }

    // MARK: - Change detection

    /// Whether a fresh scan differs from a stored snapshot under the same rules
    /// Recent Changes renders from. A `.failed` domain carries no evidence, so
    /// only its coverage flip counts.
    public func evidenceChanged(
        since snapshotID: SnapshotID,
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        coverage: SnapshotDomainCoverage
    ) async throws -> Bool {
        if try await self.coverage(snapshotID: snapshotID) != coverage { return true }
        if coverage.tcc != .failed {
            let stored = try await readTCCGrants(snapshotID: snapshotID)
            if Self.diffTCCGrants(before: stored, after: grants).hasContent { return true }
        }
        if coverage.btm != .failed {
            let stored = try await readBTMItems(snapshotID: snapshotID)
            if Self.diffBTMItems(before: stored, after: btmItems).hasContent { return true }
        }
        if coverage.launchAgents != .failed {
            let stored = try await readLaunchAgents(snapshotID: snapshotID)
            let compareDisabled = try await launchAgentDisabledCaptured(from: snapshotID, to: snapshotID)
            let diff = Self.diffLaunchAgents(before: stored, after: launchAgents, compareDisabled: compareDisabled)
            if diff.hasContent { return true }
        }
        return false
    }

    // MARK: - Diff engine

    static func computeDiff<Item, Diff>(
        before: [Item],
        after: [Item],
        identity: (Item) -> String,
        equivalent: (Item, Item) -> Bool,
        wrap: ([Item], [Item], [DomainChange<Item>]) -> Diff
    ) -> Diff where Item: Sendable & Hashable {
        // Collapse on duplicate identity keys instead of trapping. Two TCC
        // grants legitimately share an identity key when the client is
        // path-based and carries no bundle ID — both map to e.g.
        // "filesAndFolders||". `Dictionary(uniqueKeysWithValues:)` fatal-
        // errors on that; `uniquingKeysWith` keeps the first, which is all
        // a presence-based diff needs.
        let beforeByKey = Dictionary(
            before.map { (identity($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let afterByKey = Dictionary(
            after.map { (identity($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let beforeKeys = Set(beforeByKey.keys)
        let afterKeys = Set(afterByKey.keys)

        // Derive added/removed from the deduped maps so the result stays
        // consistent with beforeByKey/afterByKey (no phantom duplicate rows).
        let added = afterKeys.subtracting(beforeKeys).sorted().map { afterByKey[$0]! }
        let removed = beforeKeys.subtracting(afterKeys).sorted().map { beforeByKey[$0]! }

        let shared = beforeKeys.intersection(afterKeys).sorted()
        let changed: [DomainChange<Item>] = shared.compactMap { key in
            let b = beforeByKey[key]!
            let a = afterByKey[key]!
            return equivalent(b, a) ? nil : DomainChange(before: b, after: a)
        }
        return wrap(added, removed, changed)
    }

    // MARK: - Identity keys

    static func launchAgentIdentityKey(_ item: LaunchAgentItem) -> String {
        "\(item.sourceDirectory.rawValue)|\(item.label)"
    }

    func launchAgentDisabledCaptured(
        from beforeSnapshotID: SnapshotID,
        to afterSnapshotID: SnapshotID
    ) async throws -> Bool {
        try await dbQueue.read { db in
            for snapshotID in [beforeSnapshotID, afterSnapshotID] {
                let marker = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT launch_agent_disabled_captured
                        FROM snapshots
                        WHERE id = ?
                        """,
                    arguments: [snapshotID.rawValue]
                ) ?? 0
                guard marker == 1 else { return false }
            }
            return true
        }
    }

    static func launchAgentsEquivalent(
        _ lhs: LaunchAgentItem,
        _ rhs: LaunchAgentItem,
        compareDisabled: Bool
    ) -> Bool {
        lhs.label == rhs.label
            && lhs.sourceDirectory == rhs.sourceDirectory
            && lhs.programPath == rhs.programPath
            && lhs.programArguments == rhs.programArguments
            && lhs.runAtLoad == rhs.runAtLoad
            && lhs.keepAlive == rhs.keepAlive
            && (!compareDisabled || lhs.isDisabled == rhs.isDisabled)
    }

    static func tccGrantIdentityKey(_ grant: PermissionGrant) -> String {
        grant.identityKey
    }

    static func btmItemIdentityKey(_ item: BTMItem) -> String {
        item.identifier
    }
}
