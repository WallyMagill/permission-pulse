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

    /// `services` limits both endpoints to those services, for a baseline
    /// that saw more than the later scan can.
    public func diffTCCGrants(
        from: SnapshotID,
        to: SnapshotID,
        limitedTo services: Set<PermissionService>? = nil
    ) async throws -> TCCGrantsDiff {
        let included: (PermissionGrant) -> Bool = { services?.contains($0.service) ?? true }
        return Self.diffTCCGrants(
            before: try await readTCCGrants(snapshotID: from).filter(included),
            after: try await readTCCGrants(snapshotID: to).filter(included)
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
            wrap: { added, removed, changed in
                LaunchAgentsDiff(
                    added: added,
                    removed: removed,
                    changed: compareDisabled ? changed : changed.map(carryingUncapturedDisabled)
                )
            }
        )
    }

    // A legacy endpoint never captured `isDisabled`; its stored `false` is a
    // placeholder, so a change row must not describe it as a transition.
    private static func carryingUncapturedDisabled(
        _ change: DomainChange<LaunchAgentItem>
    ) -> DomainChange<LaunchAgentItem> {
        let before = change.before
        return DomainChange(
            before: LaunchAgentItem(
                label: before.label,
                sourceDirectory: before.sourceDirectory,
                programPath: before.programPath,
                programArguments: before.programArguments,
                runAtLoad: before.runAtLoad,
                keepAlive: before.keepAlive,
                isDisabled: change.after.isDisabled,
                detailsReadable: before.detailsReadable,
                fileName: before.fileName
            ),
            after: change.after
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
            equivalent: tccGrantsEquivalent,
            wrap: { TCCGrantsDiff(added: $0, removed: $1, changed: $2) }
        )
    }

    public static func diffBTMItems(before: [BTMItem], after: [BTMItem]) -> BTMItemsDiff {
        computeDiff(
            before: before,
            after: after,
            identity: btmItemIdentityKey,
            equivalent: btmItemsEquivalent,
            wrap: { BTMItemsDiff(added: $0, removed: $1, changed: $2) }
        )
    }

    // MARK: - Change detection

    /// Whether a fresh scan differs from a stored snapshot under the same rules
    /// Recent Changes renders from. A `.failed` domain carries no evidence, so
    /// only its coverage flip counts. Fresh items are first passed through the
    /// store's own date encoding: stored dates keep millisecond precision, so
    /// a raw in-memory date would never compare equal and every scan would
    /// look changed.
    public func evidenceChanged(
        since snapshotID: SnapshotID,
        grants: [PermissionGrant],
        launchAgents: [LaunchAgentItem],
        btmItems: [BTMItem],
        coverage: SnapshotDomainCoverage
    ) async throws -> Bool {
        if try await self.coverage(snapshotID: snapshotID) != coverage {
            return Self.changed("coverage")
        }
        if coverage.tcc != .failed {
            let stored = try await readTCCGrants(snapshotID: snapshotID)
            let fresh = grants.map(Self.storageNormalized)
            if Self.diffTCCGrants(before: stored, after: fresh).hasContent { return Self.changed("tcc") }
        }
        if coverage.btm != .failed {
            let stored = try await readBTMItems(snapshotID: snapshotID)
            let fresh = btmItems.map(Self.storageNormalized)
            if Self.diffBTMItems(before: stored, after: fresh).hasContent { return Self.changed("btm") }
        }
        if coverage.launchAgents != .failed {
            let stored = try await readLaunchAgents(snapshotID: snapshotID)
            let compareDisabled = try await launchAgentDisabledCaptured(from: snapshotID, to: snapshotID)
            let diff = Self.diffLaunchAgents(before: stored, after: launchAgents, compareDisabled: compareDisabled)
            if diff.hasContent { return Self.changed("launchAgents") }
        }
        return false
    }

    private static func changed(_ domain: String) -> Bool {
        logger.info("Evidence changed: \(domain, privacy: .public)")
        return true
    }

    static func storageNormalized(_ date: Date) -> Date {
        Date.fromDatabaseValue(date.databaseValue) ?? date
    }

    static func storageNormalized(_ grant: PermissionGrant) -> PermissionGrant {
        PermissionGrant(
            service: grant.service,
            app: grant.app,
            lastModified: storageNormalized(grant.lastModified),
            automationTarget: grant.automationTarget,
            authValue: grant.authValue
        )
    }

    static func storageNormalized(_ item: BTMItem) -> BTMItem {
        BTMItem(
            identifier: item.identifier,
            name: item.name,
            developerName: item.developerName,
            bundleIdentifier: item.bundleIdentifier,
            teamIdentifier: item.teamIdentifier,
            type: item.type,
            disposition: item.disposition,
            dispositionRaw: item.dispositionRaw,
            scope: item.scope,
            modificationDate: storageNormalized(item.modificationDate),
            parentIdentifier: item.parentIdentifier
        )
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

    // `fileName` is deliberately excluded: pre-v7 rows store NULL, so including
    // it would report every agent as changed on the first scan after upgrade.
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
            && lhs.detailsReadable == rhs.detailsReadable
            && (!compareDisabled || lhs.isDisabled == rhs.isDisabled)
    }

    static func tccGrantIdentityKey(_ grant: PermissionGrant) -> String {
        grant.identityKey
    }

    static func btmItemIdentityKey(_ item: BTMItem) -> String {
        item.identityKey
    }

    // A change row must describe something the user can see changed. Names,
    // paths and modification dates churn on app updates without any change
    // to what an app may do, so only the authorization state counts.
    static func tccGrantsEquivalent(_ lhs: PermissionGrant, _ rhs: PermissionGrant) -> Bool {
        lhs.authValue == rhs.authValue
    }

    // Same rule for background items: enabled/disabled and the item's kind.
    // The raw disposition bits, display names and dates are excluded.
    static func btmItemsEquivalent(_ lhs: BTMItem, _ rhs: BTMItem) -> Bool {
        lhs.disposition == rhs.disposition && lhs.type == rhs.type
    }
}
