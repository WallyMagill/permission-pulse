import Foundation
import OSLog
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI

@MainActor
final class SnapshotCoordinator {
    private static let logger = Logger(
        subsystem: "com.wallymagill.permissionpulse",
        category: "snapshot-coordinator"
    )

    static let lastSnapshotDateKey = "com.wallymagill.permissionpulse.lastSnapshotDate"
    static let lastReviewedSnapshotIDKey = "com.wallymagill.permissionpulse.lastReviewedSnapshotID"
    static let defaultSnapshotRetentionDays = 90
    static let defaultStaleThresholdDays = 90
    static let weekWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
    static let maxStaleProbesInFlight = 8

    private let viewModel: AppViewModel
    private let store: SnapshotStore
    private let lastUsedProbe: any LastUsedProbe
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let dismissedStaleApps: DismissedStaleAppStore?

    private let snapshotRetentionDays: @MainActor () -> Int
    private let staleThresholdDays: @MainActor () -> Int

    init(
        viewModel: AppViewModel,
        store: SnapshotStore,
        lastUsedProbe: any LastUsedProbe = LastUsedProbeHybrid(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @Sendable @escaping () -> Date = Date.init,
        snapshotRetentionDays: @MainActor @escaping () -> Int = {
            SnapshotCoordinator.defaultSnapshotRetentionDays
        },
        staleThresholdDays: @MainActor @escaping () -> Int = {
            SnapshotCoordinator.defaultStaleThresholdDays
        },
        dismissedStaleApps: DismissedStaleAppStore? = nil
    ) {
        self.viewModel = viewModel
        self.store = store
        self.lastUsedProbe = lastUsedProbe
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.snapshotRetentionDays = snapshotRetentionDays
        self.staleThresholdDays = staleThresholdDays
        self.dismissedStaleApps = dismissedStaleApps
        // A constructed coordinator implies the store opened successfully, so
        // clear any stale "unavailable" banner (e.g. after a successful Reset). (C2)
        viewModel.snapshotStoreUnavailable = false
    }

    func onScanCompleted() async {
        let retentionDays = snapshotRetentionDays()
        let thresholdDays = staleThresholdDays()
        viewModel.staleThresholdDays = thresholdDays

        var latestID: SnapshotID?
        do {
            latestID = try await store.latestSnapshotID()
        } catch {
            // Without knowing the latest snapshot, a write would skip the
            // change check and duplicate history; try again next scan.
            Self.logger.error("Latest snapshot lookup failed: \(error.localizedDescription, privacy: .public)")
            viewModel.diffUnavailable = true
            return
        }
        if let written = await writeSnapshotIfChanged(since: latestID, retentionDays: retentionDays) {
            latestID = written
        }
        await refreshDiffsAndStale(latestID: latestID, thresholdDays: thresholdDays)
    }

    /// Writes when there is no history yet or the evidence differs from the
    /// latest snapshot. Returns the new snapshot's ID, or nil when nothing
    /// was written.
    private func writeSnapshotIfChanged(
        since latestID: SnapshotID?,
        retentionDays: Int
    ) async -> SnapshotID? {
        let coverage = currentCoverage()
        guard coverage != Self.nothingCaptured else {
            Self.logger.info("Snapshot skipped — every domain failed")
            return nil
        }
        do {
            if let latestID, try await !store.evidenceChanged(
                since: latestID,
                grants: viewModel.grants,
                launchAgents: viewModel.launchAgents,
                btmItems: viewModel.btmItems,
                coverage: coverage
            ) {
                Self.logger.info("Snapshot skipped — evidence unchanged")
                return nil
            }
            let today = now()
            let snapshotID = try await store.writeSnapshot(
                grants: viewModel.grants,
                launchAgents: viewModel.launchAgents,
                btmItems: viewModel.btmItems,
                coverage: coverage,
                at: today
            )
            Self.logger.info("Snapshot \(snapshotID.rawValue) written")
            persistLastSnapshotDate(today)
            await prune(retentionDays: retentionDays, today: today)
            return snapshotID
        } catch {
            Self.logger.error("Snapshot write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func prune(retentionDays: Int, today: Date) async {
        // Day-aligned like the diff windows: a wall-clock cutoff at 7-day
        // retention would prune the "Last 7 days" baseline.
        let startOfToday = calendar.startOfDay(for: today)
        let retentionCutoff = calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: startOfToday
        ) ?? startOfToday.addingTimeInterval(-Double(retentionDays) * 86_400)
        // A prune failure must not abort the diff refresh, so it is logged
        // here rather than propagated — otherwise the DB grows unbounded with
        // no signal. (R1)
        do {
            _ = try await store.pruneSnapshots(olderThan: retentionCutoff)
        } catch {
            Self.logger.error("Snapshot prune failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func markCurrentSnapshotReviewed() {
        guard let id = viewModel.latestSnapshotID else { return }
        viewModel.lastReviewedSnapshotID = id
        defaults.set(id.rawValue, forKey: Self.lastReviewedSnapshotIDKey)
    }

    // MARK: - Private

    private static let nothingCaptured = SnapshotDomainCoverage(
        tcc: .failed,
        btm: .failed,
        launchAgents: .failed
    )

    private func currentCoverage() -> SnapshotDomainCoverage {
        let tcc = Self.coverage(of: viewModel.tccAvailability)
        return SnapshotDomainCoverage(
            tcc: tcc == .complete && !viewModel.tccUnavailableSources.isEmpty ? .reduced : tcc,
            btm: Self.coverage(of: viewModel.btmAvailability),
            launchAgents: Self.coverage(of: viewModel.launchAgentAvailability)
        )
    }

    private static func coverage(of availability: ScanAvailability) -> SnapshotCoverage {
        switch availability {
        case .complete: .complete
        case .degraded: .degraded
        case .failed, .never: .failed
        }
    }

    private func persistLastSnapshotDate(_ date: Date) {
        let iso = ISO8601DateFormatter().string(from: date)
        defaults.set(iso, forKey: Self.lastSnapshotDateKey)
    }

    private func refreshDiffsAndStale(latestID: SnapshotID?, thresholdDays: Int) async {
        viewModel.diffUnavailable = false
        guard let latestID else { return }
        viewModel.latestSnapshotID = latestID

        // Defensive: if a stored lastReviewedSnapshotID points past the current
        // latest (could happen if snapshots.db was deleted while UserDefaults
        // survived), clear it. Restore otherwise.
        let storedReviewedRaw = defaults.object(forKey: Self.lastReviewedSnapshotIDKey) as? Int64
        if let raw = storedReviewedRaw {
            if raw > latestID.rawValue {
                defaults.removeObject(forKey: Self.lastReviewedSnapshotIDKey)
                viewModel.lastReviewedSnapshotID = nil
            } else {
                viewModel.lastReviewedSnapshotID = SnapshotID(rawValue: raw)
            }
        } else {
            viewModel.lastReviewedSnapshotID = nil
        }

        viewModel.latestSnapshotDate = try? await store.snapshotDate(snapshotID: latestID)

        let nowDate = now()
        // Anchor diff baselines to calendar-day boundaries, not a rolling
        // window: "Yesterday" means the state at the start of today.
        // `latestSnapshotID(atOrBefore:)` is inclusive (<=): snapshots written
        // today have timestamps after startOfToday and are excluded; the most
        // recent prior-day snapshot is <= startOfToday and is selected. (C1)
        let startOfToday = calendar.startOfDay(for: nowDate)
        let weekCutoff = calendar.date(byAdding: .day, value: -7, to: startOfToday)
            ?? startOfToday.addingTimeInterval(-Self.weekWindowSeconds)

        viewModel.latestDiffYesterday = await computeDiffs(cutoff: startOfToday, latestID: latestID)
        viewModel.latestDiffWeek = await computeDiffs(cutoff: weekCutoff, latestID: latestID)
        viewModel.staleApps = await computeStaleApps(
            nowDate: nowDate,
            thresholdDays: thresholdDays
        )
    }

    private func computeDiffs(cutoff: Date, latestID: SnapshotID) async -> SnapshotDiffs? {
        do {
            guard let fromID = try await store.latestSnapshotID(atOrBefore: cutoff) else {
                return nil
            }
            // Snapshots are written only on change, so a baseline equal to the
            // latest means nothing changed in the window.
            guard fromID != latestID else {
                return Self.noChanges(at: latestID, coverage: try await store.coverage(snapshotID: latestID))
            }
            return try await diffs(from: fromID, to: latestID)
        } catch {
            Self.logger.error("Diff query failed: \(error.localizedDescription, privacy: .public)")
            viewModel.diffUnavailable = true   // (C2) error, not "no data yet"
            return nil
        }
    }

    /// "Nothing changed" only holds for domains the snapshot captured fully;
    /// the rest are reported as uncompared rather than silently clean.
    private static func noChanges(at id: SnapshotID, coverage: SnapshotDomainCoverage) -> SnapshotDiffs {
        SnapshotDiffs(
            fromID: id,
            toID: id,
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: []),
            uncomparedDomains: incompleteDomains(coverage)
        )
    }

    private static func incompleteDomains(_ coverage: SnapshotDomainCoverage) -> [HistoryDomain] {
        [
            coverage.tcc.capturedFullScope ? nil : HistoryDomain.tcc,
            coverage.btm.capturedFullScope ? nil : .btm,
            coverage.launchAgents.capturedFullScope ? nil : .launchAgents,
        ].compactMap { $0 }
    }

    /// Compares a domain only when both endpoints captured the same full
    /// scope; a partial or narrower endpoint would turn omitted items into
    /// false removals.
    private func diffs(from fromID: SnapshotID, to toID: SnapshotID) async throws -> SnapshotDiffs {
        let before = try await store.coverage(snapshotID: fromID)
        let after = try await store.coverage(snapshotID: toID)
        let comparable: (KeyPath<SnapshotDomainCoverage, SnapshotCoverage>) -> Bool = {
            before[keyPath: $0].isComparable(with: after[keyPath: $0])
        }
        let tcc = comparable(\.tcc)
            ? try await store.diffTCCGrants(from: fromID, to: toID)
            : TCCGrantsDiff(added: [], removed: [])
        let btm = comparable(\.btm)
            ? try await store.diffBTMItems(from: fromID, to: toID)
            : BTMItemsDiff(added: [], removed: [])
        let launchAgents = comparable(\.launchAgents)
            ? try await store.diffLaunchAgents(from: fromID, to: toID)
            : LaunchAgentsDiff(added: [], removed: [])
        let uncompared: [HistoryDomain] = [
            comparable(\.tcc) ? nil : .tcc,
            comparable(\.btm) ? nil : .btm,
            comparable(\.launchAgents) ? nil : .launchAgents,
        ].compactMap { $0 }
        return SnapshotDiffs(
            fromID: fromID,
            toID: toID,
            tcc: tcc,
            btm: btm,
            launchAgents: launchAgents,
            uncomparedDomains: uncompared
        )
    }

    private func computeStaleApps(nowDate: Date, thresholdDays: Int) async -> [StaleApp] {
        // Dedupe grants by stable app identity, keep only those with a bundlePath.
        // Drop anything the user has chosen to skip in Preferences so the
        // sidebar badge count stays honest end-to-end.
        let skipped = dismissedStaleApps?.allStableKeys() ?? []
        var grouped: [String: [PermissionGrant]] = [:]
        for grant in viewModel.grants {
            guard let stableKey = grant.app.stableKey,
                  !skipped.contains(stableKey) else { continue }
            grouped[stableKey, default: []].append(grant)
        }
        let candidates: [StaleCandidate] = grouped.compactMap { _, grants in
            guard let representative = grants.first(where: { $0.app.bundlePath != nil }),
                  let path = representative.app.bundlePath else { return nil }
            let services = grants.map(\.service)
            return StaleCandidate(app: representative.app, path: path, services: services)
        }

        let probe = lastUsedProbe
        let cal = calendar
        let limit = Self.maxStaleProbesInFlight

        let stale: [StaleApp] = await withTaskGroup(of: StaleApp?.self) { group in
            var iterator = candidates.makeIterator()
            // Prime the pump with up to `limit` in-flight probes.
            for _ in 0..<limit {
                guard let c = iterator.next() else { break }
                group.addTask {
                    await Self.probeOne(
                        candidate: c,
                        probe: probe,
                        now: nowDate,
                        threshold: thresholdDays,
                        calendar: cal
                    )
                }
            }

            var results: [StaleApp] = []
            while let maybeStale = await group.next() {
                if let stale = maybeStale { results.append(stale) }
                if let c = iterator.next() {
                    group.addTask {
                        await Self.probeOne(
                            candidate: c,
                            probe: probe,
                            now: nowDate,
                            threshold: thresholdDays,
                            calendar: cal
                        )
                    }
                }
            }
            return results
        }

        return stale.sorted { $0.lastUsedDate < $1.lastUsedDate }
    }

    private static func probeOne(
        candidate: StaleCandidate,
        probe: any LastUsedProbe,
        now: Date,
        threshold: Int,
        calendar: Calendar
    ) async -> StaleApp? {
        guard let probed = await probe.lastUsedDate(for: candidate.path) else {
            return nil
        }
        let days = calendar.dateComponents([.day], from: probed.date, to: now).day ?? 0
        guard days >= threshold else { return nil }
        return StaleApp(
            app: candidate.app,
            lastUsedDate: probed.date,
            dateSource: probed.source,
            daysSinceUsed: days,
            grantedServices: candidate.services
        )
    }
}

private struct StaleCandidate: Sendable {
    let app: AppIdentity
    let path: URL
    let services: [PermissionService]
}
