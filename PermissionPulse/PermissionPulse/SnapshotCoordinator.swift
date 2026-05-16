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
    static let yesterdayWindowSeconds: TimeInterval = 24 * 60 * 60
    static let weekWindowSeconds: TimeInterval = 7 * 24 * 60 * 60
    static let maxStaleProbesInFlight = 8

    private let viewModel: AppViewModel
    private let store: SnapshotStore
    private let lastUsedProbe: any LastUsedProbe
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let dismissedStaleApps: DismissedStaleAppStore?

    // Injected so Preferences can change them at runtime. New values take
    // effect on the next scan cycle — we do not re-prune mid-session to
    // avoid surprise data deletion when the user drags a slider.
    private let snapshotRetentionDays: Int
    private let staleThresholdDays: Int

    init(
        viewModel: AppViewModel,
        store: SnapshotStore,
        lastUsedProbe: any LastUsedProbe = LastUsedProbeHybrid(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @Sendable @escaping () -> Date = Date.init,
        snapshotRetentionDays: Int = SnapshotCoordinator.defaultSnapshotRetentionDays,
        staleThresholdDays: Int = SnapshotCoordinator.defaultStaleThresholdDays,
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
    }

    func onScanCompleted() async {
        guard scanFullySucceeded() else {
            Self.logger.debug("Skipping snapshot — at least one scanner errored")
            return
        }

        let today = now()
        if let lastDate = lastSnapshotDate(), calendar.isDate(lastDate, inSameDayAs: today) {
            // Same calendar day — don't write, but still refresh diffs in case
            // the user has not seen this snapshot since launch.
            Self.logger.debug("Snapshot already written today; refreshing diffs only")
            await refreshDiffsAndStale(latestID: try? await store.latestSnapshotID())
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
                value: -snapshotRetentionDays,
                to: today
            ) ?? today.addingTimeInterval(-Double(snapshotRetentionDays) * 86_400)
            _ = try? await store.pruneSnapshots(olderThan: retentionCutoff)
            await refreshDiffsAndStale(latestID: snapshotID)
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
        viewModel.tccScanError == nil && viewModel.btmScanError == nil
    }

    private func lastSnapshotDate() -> Date? {
        guard let iso = defaults.string(forKey: Self.lastSnapshotDateKey) else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private func persistLastSnapshotDate(_ date: Date) {
        let iso = ISO8601DateFormatter().string(from: date)
        defaults.set(iso, forKey: Self.lastSnapshotDateKey)
    }

    private func refreshDiffsAndStale(latestID: SnapshotID?) async {
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
        let yesterdayCutoff = nowDate.addingTimeInterval(-Self.yesterdayWindowSeconds)
        let weekCutoff = nowDate.addingTimeInterval(-Self.weekWindowSeconds)

        viewModel.latestDiffYesterday = await computeDiffs(cutoff: yesterdayCutoff, latestID: latestID)
        viewModel.latestDiffWeek = await computeDiffs(cutoff: weekCutoff, latestID: latestID)
        viewModel.staleApps = await computeStaleApps(nowDate: nowDate)
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
            return nil
        }
    }

    private func computeStaleApps(nowDate: Date) async -> [StaleApp] {
        // Dedupe grants by bundleID, keep only those with a bundlePath.
        // Drop anything the user has chosen to skip in Preferences so the
        // sidebar badge count stays honest end-to-end.
        let skipped = dismissedStaleApps?.allBundleIDs() ?? []
        let grouped = Dictionary(grouping: viewModel.grants, by: \.app.bundleID)
            .filter { bundleID, _ in !skipped.contains(bundleID) }
        let candidates: [StaleCandidate] = grouped.compactMap { _, grants in
            guard let representative = grants.first,
                  let path = representative.app.bundlePath else { return nil }
            let services = grants.map(\.service)
            return StaleCandidate(app: representative.app, path: path, services: services)
        }

        let threshold = staleThresholdDays
        let probe = lastUsedProbe
        let cal = calendar
        let limit = Self.maxStaleProbesInFlight

        let stale: [StaleApp] = await withTaskGroup(of: StaleApp?.self) { group in
            var iterator = candidates.makeIterator()
            // Prime the pump with up to `limit` in-flight probes.
            for _ in 0..<limit {
                guard let c = iterator.next() else { break }
                group.addTask {
                    await Self.probeOne(candidate: c, probe: probe, now: nowDate, threshold: threshold, calendar: cal)
                }
            }

            var results: [StaleApp] = []
            while let maybeStale = await group.next() {
                if let stale = maybeStale { results.append(stale) }
                if let c = iterator.next() {
                    group.addTask {
                        await Self.probeOne(candidate: c, probe: probe, now: nowDate, threshold: threshold, calendar: cal)
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
