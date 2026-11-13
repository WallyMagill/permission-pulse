import Foundation
import GRDB
import PermissionsCore

extension SnapshotStore {
    // MARK: - Snapshot diffs

    public func diffLaunchAgents(
        from: SnapshotID,
        to: SnapshotID
    ) async throws -> LaunchAgentsDiff {
        let facts = try await comparableFacts(from: from, to: to)
        return Self.diffLaunchAgents(
            before: try await readLaunchAgents(snapshotID: from),
            after: try await readLaunchAgents(snapshotID: to),
            compareDisabled: facts.disabled,
            compareArguments: facts.arguments
        )
    }

    /// `services` limits both endpoints to those services, for a baseline
    /// that saw more than the later scan can.
    public func diffTCCGrants(
        from: SnapshotID,
        to: SnapshotID,
        limitedTo services: Set<PermissionService>? = nil
    ) async throws -> TCCGrantsDiff {
        let excluded = try await comparableFacts(from: from, to: to).uncapturedServices
        let included: (PermissionGrant) -> Bool = {
            !excluded.contains($0.service) && (services?.contains($0.service) ?? true)
        }
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

    /// `compareDisabled` / `compareArguments` false: an endpoint did not
    /// capture that field the way the other did, so it is not compared and a
    /// change row for another field shows the later value on both sides.
    public static func diffLaunchAgents(
        before: [LaunchAgentItem],
        after: [LaunchAgentItem],
        compareDisabled: Bool,
        compareArguments: Bool = true
    ) -> LaunchAgentsDiff {
        computeDiff(
            before: before,
            after: after,
            identity: launchAgentIdentityKey,
            equivalent: {
                launchAgentsEquivalent(
                    $0, $1,
                    compareDisabled: compareDisabled,
                    compareArguments: compareArguments
                )
            },
            wrap: { added, removed, changed in
                LaunchAgentsDiff(
                    added: added,
                    removed: removed,
                    changed: changed.map {
                        carryingUncaptured($0, disabled: !compareDisabled, arguments: !compareArguments)
                    }
                )
            }
        )
    }

    private static func carryingUncaptured(
        _ change: DomainChange<LaunchAgentItem>,
        disabled: Bool,
        arguments: Bool
    ) -> DomainChange<LaunchAgentItem> {
        guard disabled || arguments else { return change }
        let before = change.before
        return DomainChange(
            before: LaunchAgentItem(
                label: before.label,
                sourceDirectory: before.sourceDirectory,
                programPath: before.programPath,
                programArguments: arguments ? change.after.programArguments : before.programArguments,
                runAtLoad: before.runAtLoad,
                keepAlive: before.keepAlive,
                isDisabled: disabled ? change.after.isDisabled : before.isDisabled,
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
        // Older capture rules missed facts this scan records, so the first
        // scan after an upgrade always writes a current-generation baseline.
        if try await captureGeneration(snapshotID: snapshotID) != CaptureGeneration.current {
            return Self.changed("captureGeneration")
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
            let facts = try await comparableFacts(from: snapshotID, to: snapshotID)
            let diff = Self.diffLaunchAgents(before: stored, after: launchAgents, compareDisabled: facts.disabled)
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

    /// What both endpoints captured under the same rules. A legacy snapshot
    /// (`launch_agent_disabled_captured = 0`) stored `isDisabled` as a
    /// placeholder; a pair spanning capture generation 2 differs in the facts
    /// `CaptureGeneration` lists.
    func comparableFacts(
        from beforeSnapshotID: SnapshotID,
        to afterSnapshotID: SnapshotID
    ) async throws -> ComparableFacts {
        try await dbQueue.read { db in
            var disabledCaptured = true
            var generations: [Int] = []
            for id in [beforeSnapshotID, afterSnapshotID] {
                let marker = try Int.fetchOne(
                    db,
                    sql: "SELECT launch_agent_disabled_captured FROM snapshots WHERE id = ?",
                    arguments: [id.rawValue]
                )
                disabledCaptured = disabledCaptured && marker == 1
                generations.append(try Self.captureGeneration(db, snapshotID: id))
            }
            let spans = CaptureGeneration.spansGeneration2(generations[0], generations[1])
            return ComparableFacts(
                disabled: disabledCaptured && !spans,
                arguments: !spans,
                uncapturedServices: spans ? CaptureGeneration.servicesAddedInGeneration2 : []
            )
        }
    }

    func captureGeneration(snapshotID: SnapshotID) async throws -> Int {
        try await dbQueue.read { db in try Self.captureGeneration(db, snapshotID: snapshotID) }
    }

    private static func captureGeneration(_ db: Database, snapshotID: SnapshotID) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT capture_generation FROM snapshots WHERE id = ?",
            arguments: [snapshotID.rawValue]
        ) ?? 1
    }

    // `fileName` is deliberately excluded: pre-v7 rows store NULL, so including
    // it would report every agent as changed on the first scan after upgrade.
    static func launchAgentsEquivalent(
        _ lhs: LaunchAgentItem,
        _ rhs: LaunchAgentItem,
        compareDisabled: Bool,
        compareArguments: Bool = true
    ) -> Bool {
        lhs.label == rhs.label
            && lhs.sourceDirectory == rhs.sourceDirectory
            && lhs.programPath == rhs.programPath
            && (!compareArguments || lhs.programArguments == rhs.programArguments)
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

struct ComparableFacts {
    let disabled: Bool
    let arguments: Bool
    let uncapturedServices: Set<PermissionService>
}
