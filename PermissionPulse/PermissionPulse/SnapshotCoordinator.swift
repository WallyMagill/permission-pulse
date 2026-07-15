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

        guard scanFullySucceeded() else {
            Self.logger.debug("Skipping snapshot — at least one scanner is not complete")
            return
        }

        let today = now()
        if let lastDate = lastSnapshotDate(), calendar.isDate(lastDate, inSameDayAs: today) {
            // Same calendar day — don't write, but still refresh diffs in case
            // the user has not seen this snapshot since launch.
            Self.logger.debug("Snapshot already written today; refreshing diffs only")
            await refreshDiffsAndStale(
                latestID: try? await store.latestSnapshotID(),
                thresholdDays: thresholdDays
            )
            return
        }

        do {
            let snapshotID = try await store.writeFullSnapshot(
                grants: viewModel.grants,
                launchAgents: viewModel.launchAgents,
                btmItems: viewModel.btmItems,
                at: today
            )
            persistLastSnapshotDate(today)
            let retentionCutoff = calendar.date(
                byAdding: .day,
                value: -retentionDays,
                to: today
            ) ?? today.addingTimeInterval(-Double(retentionDays) * 86_400)
            // A prune failure must NOT abort the diff refresh below, so it gets
            // its own do/catch (not the outer one) and is logged rather than
            // swallowed — otherwise the DB grows unbounded with no signal. (R1)
            do {
                _ = try await store.pruneSnapshots(olderThan: retentionCutoff)
            } catch {
                Self.logger.error("Snapshot prune failed: \(error.localizedDescription, privacy: .public)")
            }
            await refreshDiffsAndStale(latestID: snapshotID, thresholdDays: thresholdDays)
        } catch {
            Self.logger.error(
                "Snapshot write failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func markCurrentSnapshotReviewed() {
        guard let id = viewModel.latestSnapshotID else { return }
        viewModel.lastReviewedSnapshotID = id
        defaults.set(id.rawValue, forKey: Self.lastReviewedSnapshotIDKey)
    }

    // MARK: - Private

    private func scanFullySucceeded() -> Bool {
        viewModel.tccAvailability.isComplete
            && viewModel.btmAvailability.isComplete
            && viewModel.launchAgentAvailability.isComplete
    }

    private func lastSnapshotDate() -> Date? {
        guard let iso = defaults.string(forKey: Self.lastSnapshotDateKey) else { return nil }
        return ISO8601DateFormatter().date(from: iso)
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

        let nowDate = now()
        // Anchor diff baselines to calendar-day boundaries, not a rolling
        // window, because snapshots are written at most once per calendar day.
        // `latestSnapshotID(atOrBefore:)` is inclusive (<=): today's snapshot
        // has a timestamp after startOfToday and is excluded; the most recent
        // prior-day snapshot is <= startOfToday and is selected. (C1)
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
            guard let fromID = try await store.latestSnapshotID(atOrBefore: cutoff),
                  fromID != latestID else {
                return nil
            }
            async let tccTask = store.diffTCCGrants(from: fromID, to: latestID)
            async let btmTask = store.diffBTMItems(from: fromID, to: latestID)
            async let laTask  = store.diffLaunchAgents(from: fromID, to: latestID)
            let (tcc, btm, la) = try await (tccTask, btmTask, laTask)
            return SnapshotDiffs(
                fromID: fromID,
                toID: latestID,
                tcc: tcc,
                btm: btm,
                launchAgents: la
            )
        } catch {
            Self.logger.error("Diff query failed: \(error.localizedDescription, privacy: .public)")
            viewModel.diffUnavailable = true   // (C2) error, not "no data yet"
            return nil
        }
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
