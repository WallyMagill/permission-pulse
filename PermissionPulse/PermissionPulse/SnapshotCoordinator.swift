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
    private let store: any SnapshotHistoryStore
    private let lastUsedProbe: any LastUsedProbe
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let dismissedStaleApps: DismissedStaleAppStore?

    private let snapshotRetentionDays: @MainActor () -> Int
    private let staleThresholdDays: @MainActor () -> Int
    /// Counts diff refreshes started; a refresh applies its result only if
    /// no later one started while it was reading the store.
    private var refreshesStarted = 0

    /// Called after a scan wrote a snapshot and the diffs were refreshed:
    /// the latest snapshot before the write (nil on first run), then the new one.
    var onSnapshotWritten: (@MainActor (_ previous: SnapshotID?, _ written: SnapshotID) -> Void)?

    init(
        viewModel: AppViewModel,
        store: any SnapshotHistoryStore,
        lastUsedProbe: any LastUsedProbe = LastUsedProbeHybrid(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
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

        let previousID: SnapshotID?
        do {
            previousID = try await store.latestSnapshotID()
        } catch {
            // Without knowing the latest snapshot, a write would skip the
            // change check and duplicate history; try again next scan.
            Self.logger.error("Latest snapshot lookup failed: \(error.localizedDescription, privacy: .public)")
            viewModel.diffUnavailable = true
            return
        }
        let written = await writeSnapshotIfChanged(since: previousID)
        if previousID == nil, let written {
            // The first snapshot ever (also the first after Reset All Data)
            // is the baseline: later changes show as changes since it,
            // rather than "nothing to compare" until tomorrow.
            recordReviewed(written)
        }
        let latestID = written ?? previousID
        viewModel.dismissedDiffEntries?.pruneExpired(asOf: now())
        let baselines = await refreshDiffs(latestID: latestID)
        if written != nil, let baselines {
            await prune(retentionDays: retentionDays, keeping: baselines)
        }
        guard latestID != nil else { return }
        viewModel.staleApps = await computeStaleApps(nowDate: now(), thresholdDays: thresholdDays)
        if let written { onSnapshotWritten?(previousID, written) }
    }

    /// Writes when there is no history yet or the evidence differs from the
    /// latest snapshot. Returns the new snapshot's ID, or nil when nothing
    /// was written.
    private func writeSnapshotIfChanged(since latestID: SnapshotID?) async -> SnapshotID? {
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
                viewModel.snapshotWriteFailed = false
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
            viewModel.snapshotWriteFailed = false
            persistLastSnapshotDate(today)
            return snapshotID
        } catch {
            Self.logger.error("Snapshot write failed: \(error.localizedDescription, privacy: .public)")
            viewModel.snapshotWriteFailed = true
            return nil
        }
    }

    /// `protected` holds every snapshot a current diff compares against,
    /// plus the last-reviewed one; the store keeps those past retention.
    private func prune(retentionDays: Int, keeping protected: Set<SnapshotID>) async {
        // Day-aligned like the diff windows: a wall-clock cutoff at 7-day
        // retention would prune the "Last 7 days" baseline.
        let startOfToday = calendar.startOfDay(for: now())
        let retentionCutoff = calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: startOfToday
        ) ?? startOfToday.addingTimeInterval(-Double(retentionDays) * 86_400)
        // A prune failure must not abort the diff refresh, so it is logged
        // here rather than propagated — otherwise the DB grows unbounded with
        // no signal. (R1)
        do {
            _ = try await store.pruneSnapshots(olderThan: retentionCutoff, keeping: protected)
        } catch {
            Self.logger.error("Snapshot prune failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// True when any stored snapshot captured Permissions or Background
    /// Items, both of which need Full Disk Access. Pruning keeps the newest
    /// captured snapshot of each domain, so a past capture is never lost.
    func hasCapturedProtectedData() async -> Bool {
        do {
            return try await store.snapshotSummaries(atOrBefore: .distantFuture).contains {
                $0.coverage.tcc != .failed || $0.coverage.btm != .failed
            }
        } catch {
            Self.logger.error("Capture lookup failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Marks the latest snapshot reviewed, then recomputes the
    /// since-last-review window from it. The returned task finishes when the
    /// diffs are current.
    @discardableResult
    func markCurrentSnapshotReviewed() -> Task<Void, Never>? {
        guard let id = viewModel.latestSnapshotID else { return nil }
        recordReviewed(id)
        return Task { [weak self] in
            guard let self else { return }
            await self.refreshDiffs(latestID: self.viewModel.latestSnapshotID)
        }
    }

    /// Recomputes Stale Apps from the current grants without a scan, e.g.
    /// after skipped apps are restored. Nothing to do before history exists.
    func refreshStaleApps() async {
        guard viewModel.latestSnapshotID != nil else { return }
        viewModel.staleApps = await computeStaleApps(nowDate: now(), thresholdDays: staleThresholdDays())
    }

    // MARK: - Private

    private func recordReviewed(_ id: SnapshotID) {
        viewModel.lastReviewedSnapshotID = id
        defaults.set(id.rawValue, forKey: Self.lastReviewedSnapshotIDKey)
    }

    private static let nothingCaptured = SnapshotDomainCoverage(
        tcc: .failed,
        btm: .failed,
        launchAgents: .failed
    )

    private func currentCoverage() -> SnapshotDomainCoverage {
        SnapshotDomainCoverage(
            tcc: Self.tccCoverage(
                of: viewModel.tccAvailability,
                unavailableSources: viewModel.tccUnavailableSources
            ),
            btm: Self.coverage(of: viewModel.btmAvailability),
            launchAgents: Self.coverage(of: viewModel.launchAgentAvailability)
        )
    }

    /// `.reduced` names exactly one scope — the per-user database hidden, as
    /// on macOS 27 — so two reduced snapshots always cover the same data. Any
    /// other hidden source is not a scope history can compare.
    private static func tccCoverage(
        of availability: ScanAvailability,
        unavailableSources: [ScannerSource]
    ) -> SnapshotCoverage {
        let coverage = coverage(of: availability)
        guard coverage == .complete, !unavailableSources.isEmpty else { return coverage }
        return unavailableSources == [.userTCCDatabase] ? .reduced : .degraded
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

    // Defensive: if a stored lastReviewedSnapshotID points past the current
    // latest (could happen if snapshots.db was deleted while UserDefaults
    // survived), clear it. Restore otherwise.
    private func restoreReviewedID(latestID: SnapshotID) {
        guard let raw = defaults.object(forKey: Self.lastReviewedSnapshotIDKey) as? Int64 else {
            viewModel.lastReviewedSnapshotID = nil
            return
        }
        if raw > latestID.rawValue {
            defaults.removeObject(forKey: Self.lastReviewedSnapshotIDKey)
            viewModel.lastReviewedSnapshotID = nil
        } else {
            viewModel.lastReviewedSnapshotID = SnapshotID(rawValue: raw)
        }
    }
    // MARK: - Diffs

    /// Recomputes both Recent Changes windows. Returns the snapshots they
    /// compare against plus the last-reviewed one (what pruning must keep),
    /// or nil when there is no history, a query failed, or a later refresh
    /// (a scan, or Mark as Reviewed) started meanwhile and owns the result.
    @discardableResult
    private func refreshDiffs(latestID: SnapshotID?) async -> Set<SnapshotID>? {
        refreshesStarted += 1
        let refresh = refreshesStarted
        viewModel.diffUnavailable = false
        guard let latestID else { return nil }
        viewModel.latestSnapshotID = latestID
        restoreReviewedID(latestID: latestID)
        do {
            guard let latest = try await store.snapshotSummary(id: latestID) else { return nil }
            let startOfToday = calendar.startOfDay(for: now())
            let weekCutoff = calendar.date(byAdding: .day, value: -7, to: startOfToday)
                ?? startOfToday.addingTimeInterval(-Self.weekWindowSeconds)
            let sinceReview = try await sinceReviewDiffs(latest: latest, fallbackCutoff: startOfToday)
            let week = try await diffs(cutoff: weekCutoff, latest: latest, reviewedID: nil)
            guard isCurrent(refresh) else { return nil }
            viewModel.latestSnapshotDate = latest.date
            viewModel.latestDiffSinceReview = sinceReview
            viewModel.latestDiffWeek = week
            let compared = [sinceReview, week].compactMap { $0?.baselines.values.map(\.id) }.joined()
            return Set(compared).union([viewModel.lastReviewedSnapshotID].compactMap { $0 })
        } catch {
            Self.logger.error("Diff query failed: \(error.localizedDescription, privacy: .public)")
            guard isCurrent(refresh) else { return nil }
            viewModel.latestDiffSinceReview = nil
            viewModel.latestDiffWeek = nil
            viewModel.diffUnavailable = true   // (C2) error, not "no data yet"
            return nil
        }
    }

    private func isCurrent(_ refresh: Int) -> Bool {
        guard refresh == refreshesStarted else {
            Self.logger.info("Diff refresh superseded by a later one; result dropped")
            return false
        }
        return true
    }

    /// Compared with the snapshot the user last reviewed; with none (first
    /// run, after Reset All Data, or pruned) the state at the start of today.
    private func sinceReviewDiffs(latest: SnapshotSummary, fallbackCutoff: Date) async throws -> SnapshotDiffs? {
        if let reviewedID = viewModel.lastReviewedSnapshotID,
           let reviewed = try await store.snapshotSummary(id: reviewedID) {
            return try await diffs(cutoff: reviewed.date, latest: latest, reviewedID: reviewedID)
        }
        return try await diffs(cutoff: fallbackCutoff, latest: latest, reviewedID: nil)
    }

    /// Each domain compares against its own baseline: the newest snapshot at
    /// or before `cutoff` whose coverage is comparable with the latest's. A
    /// partial or narrower endpoint would turn omitted items into false
    /// removals, so such a domain is reported as uncompared instead.
    private func diffs(cutoff: Date, latest: SnapshotSummary, reviewedID: SnapshotID?) async throws -> SnapshotDiffs? {
        var candidates = try await store.snapshotSummaries(atOrBefore: cutoff)
        if let reviewedID {
            // Newest first by (date, id), so this also drops any snapshot
            // sharing the reviewed one's timestamp but written after it.
            candidates = Array(candidates.drop { $0.id != reviewedID })
        }
        return try await diffs(latest: latest, candidates: candidates, reviewedID: reviewedID)
    }

    /// The changes from `previous` to `written` alone: a domain `previous`
    /// did not capture comparably is uncompared rather than diffed against
    /// an older snapshot. Nil when either snapshot is gone or a query fails.
    func changes(from previous: SnapshotID, to written: SnapshotID) async -> SnapshotDiffs? {
        do {
            guard let before = try await store.snapshotSummary(id: previous),
                  let after = try await store.snapshotSummary(id: written) else { return nil }
            return try await diffs(latest: after, candidates: [before], reviewedID: nil)
        } catch {
            Self.logger.error("Change query failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func diffs(
        latest: SnapshotSummary,
        candidates: [SnapshotSummary],
        reviewedID: SnapshotID?
    ) async throws -> SnapshotDiffs? {
        guard !candidates.isEmpty else { return nil }
        var choices: [HistoryDomain: BaselineChoice] = [:]
        for domain in HistoryDomain.allCases {
            choices[domain] = BaselineSelector.choose(
                latest: latest.coverage[keyPath: domain.coverage],
                candidates: candidates,
                domain: domain.coverage
            )
        }
        var narrowed = false
        if case .compared(_, systemLevelOnly: true)? = choices[.tcc] { narrowed = true }
        return SnapshotDiffs(
            toID: latest.id,
            tcc: try await diff(choices[.tcc], to: latest.id, empty: TCCGrantsDiff(added: [], removed: [])) {
                try await self.store.diffTCCGrants(
                    from: $0, to: latest.id,
                    limitedTo: narrowed ? PermissionService.systemLevel : nil
                )
            },
            btm: try await diff(choices[.btm], to: latest.id, empty: BTMItemsDiff(added: [], removed: [])) {
                try await self.store.diffBTMItems(from: $0, to: latest.id)
            },
            launchAgents: try await diff(choices[.launchAgents], to: latest.id, empty: LaunchAgentsDiff(added: [], removed: [])) {
                try await self.store.diffLaunchAgents(from: $0, to: latest.id)
            },
            baselines: choices.compactMapValues { Self.baseline($0).map { DiffBaseline(id: $0.id, date: $0.date) } },
            uncompared: choices.compactMapValues(Self.reason),
            systemLevelPermissionsOnly: narrowed,
            reviewedSnapshotID: reviewedID
        )
    }

    /// Snapshots are written only on change, so a baseline equal to the
    /// latest means nothing changed in the window.
    private func diff<Diff>(
        _ choice: BaselineChoice?,
        to latestID: SnapshotID,
        empty: Diff,
        compute: (SnapshotID) async throws -> Diff
    ) async throws -> Diff {
        guard let baseline = Self.baseline(choice), baseline.id != latestID else { return empty }
        return try await compute(baseline.id)
    }

    private static func baseline(_ choice: BaselineChoice?) -> SnapshotSummary? {
        if case .compared(let summary, _)? = choice { return summary }
        return nil
    }

    private static func reason(_ choice: BaselineChoice) -> UncomparedReason? {
        if case .notCompared(let reason) = choice { return reason }
        return nil
    }

    /// One candidate per stable app identity that has a bundle path, each
    /// service listed once. Apps the user chose to skip in Preferences are
    /// dropped so the sidebar badge count stays honest end-to-end.
    private func staleCandidates() -> [StaleCandidate] {
        let skipped = dismissedStaleApps?.allStableKeys() ?? []
        var grouped: [String: [PermissionGrant]] = [:]
        for grant in viewModel.grants {
            guard let stableKey = grant.app.stableKey,
                  !skipped.contains(stableKey) else { continue }
            grouped[stableKey, default: []].append(grant)
        }
        return grouped.compactMap { _, grants in
            guard let representative = grants.first(where: { $0.app.bundlePath != nil }),
                  let path = representative.app.bundlePath else { return nil }
            var seen = Set<PermissionService>()
            let services = grants.map(\.service).filter { seen.insert($0).inserted }
            return StaleCandidate(app: representative.app, path: path, services: services)
        }
    }

    private func computeStaleApps(nowDate: Date, thresholdDays: Int) async -> [StaleApp] {
        let candidates = staleCandidates()
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
