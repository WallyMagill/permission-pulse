import Foundation
import GRDB
import Testing
import PermissionsCore
@testable import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct SnapshotCoordinatorTests {
    @Test func skipsWriteWhenSentinelMatchesToday() async throws {
        let env = try await Environment(now: fixedNow)
        // Mark today as already written.
        env.defaults.set(
            ISO8601DateFormatter().string(from: fixedNow()),
            forKey: SnapshotCoordinator.lastSnapshotDateKey
        )

        // Also write one snapshot directly so latestSnapshotID returns non-nil
        // for the refresh path.
        _ = try await env.store.writeFullSnapshot(
            grants: [], launchAgents: [], btmItems: [], at: fixedNow()
        )
        let beforeCount = try await env.snapshotsCount()

        env.viewModel.grants = [demoGrant()]
        await env.coordinator.onScanCompleted()

        let afterCount = try await env.snapshotsCount()
        #expect(afterCount == beforeCount, "Should not have written another snapshot")
    }

    @Test func writesAfterSuccessfulScanWhenSentinelStale() async throws {
        let env = try await Environment(now: fixedNow)
        let beforeCount = try await env.snapshotsCount()
        env.viewModel.grants = [demoGrant()]
        env.viewModel.launchAgents = [demoLaunchAgent()]

        await env.coordinator.onScanCompleted()

        let afterCount = try await env.snapshotsCount()
        #expect(afterCount == beforeCount + 1)
        #expect(env.viewModel.latestSnapshotID != nil)
    }

    @Test func skipsWriteWhenAnyScannerErrored() async throws {
        let env = try await Environment(now: fixedNow)
        env.preferences.snapshotRetentionDays = 10
        env.preferences.staleThresholdDays = 30
        env.viewModel.tccScanError = .permissionDenied(reason: "FDA needed")
        env.viewModel.grants = [demoGrant()]

        let beforeCount = try await env.snapshotsCount()
        await env.coordinator.onScanCompleted()
        let afterCount = try await env.snapshotsCount()

        #expect(afterCount == beforeCount)
        #expect(env.viewModel.latestSnapshotID == nil)
        #expect(env.providers.snapshotRetentionReadCount == 1)
        #expect(env.providers.staleThresholdReadCount == 1)
        #expect(env.viewModel.staleThresholdDays == 30)
    }

    @Test func degradedAvailabilityInAnyDomainSkipsSnapshotWrite() async throws {
        let warning = ScannerWarning(source: .entries, omittedCount: 1)
        for domain in PersistedDomain.allCases {
            let env = try await Environment(now: fixedNow)
            env.viewModel.grants = [demoGrant()]
            env.viewModel.launchAgents = [demoLaunchAgent()]
            setAvailability(
                .degraded(lastUpdated: fixedNow(), warnings: [warning]),
                for: domain,
                on: env.viewModel
            )

            await env.coordinator.onScanCompleted()

            #expect(try await env.snapshotsCount() == 0, "Degraded \(domain) must not write")
        }
    }

    @Test func failedAvailabilityInAnyDomainSkipsSnapshotWrite() async throws {
        let error = ScannerError.temporarilyUnavailable(reason: "busy")
        for domain in PersistedDomain.allCases {
            let env = try await Environment(now: fixedNow)
            env.viewModel.grants = [demoGrant()]
            env.viewModel.launchAgents = [demoLaunchAgent()]
            setAvailability(
                .failed(lastSuccessful: fixedNow(), error: error),
                for: domain,
                on: env.viewModel
            )

            await env.coordinator.onScanCompleted()

            #expect(try await env.snapshotsCount() == 0, "Failed \(domain) must not write")
        }
    }

    @Test func neverAvailabilityInAnyDomainSkipsSnapshotWrite() async throws {
        for domain in PersistedDomain.allCases {
            let env = try await Environment(now: fixedNow)
            env.viewModel.grants = [demoGrant()]
            env.viewModel.launchAgents = [demoLaunchAgent()]
            setAvailability(.never, for: domain, on: env.viewModel)

            await env.coordinator.onScanCompleted()

            #expect(try await env.snapshotsCount() == 0, "Never-scanned \(domain) must not write")
        }
    }

    @Test func degradedLaunchAgentDataCannotCreateFalseRemoval() async throws {
        let env = try await Environment(now: fixedNow)
        _ = try await env.store.writeFullSnapshot(
            grants: [],
            launchAgents: [demoLaunchAgent(label: "com.example.existing")],
            btmItems: [],
            at: fixedNow().addingTimeInterval(-86_400)
        )
        let countBefore = try await env.snapshotsCount()
        env.viewModel.launchAgents = []
        env.viewModel.launchAgentAvailability = .degraded(
            lastUpdated: fixedNow(),
            warnings: [.init(source: .libraryLaunchAgents)]
        )

        await env.coordinator.onScanCompleted()

        #expect(try await env.snapshotsCount() == countBefore)
        #expect(env.viewModel.latestDiffYesterday == nil)
    }

    @Test func pushesDiffsAndStaleAppsToViewModelAfterWrite() async throws {
        // Seed an older snapshot (~36 hours ago) so the yesterday window has
        // something to diff against the new write.
        let staleBundlePath = URL(fileURLWithPath: "/Applications/StaleApp.app")
        let oldUsedDate = Date(timeIntervalSince1970: fixedNow().timeIntervalSince1970 - 200 * 86_400)
        let mock = MockLastUsedProbe(fixed: [staleBundlePath: (oldUsedDate, .spotlight)])
        let env = try await Environment(now: fixedNow, probe: mock)

        let yesterdayGrant = demoGrant(bundleID: "com.example.oldOnly")
        _ = try await env.store.writeFullSnapshot(
            grants: [yesterdayGrant],
            launchAgents: [],
            btmItems: [],
            at: fixedNow().addingTimeInterval(-36 * 60 * 60)
        )

        env.viewModel.grants = [
            demoGrant(bundleID: "com.example.staleApp", bundlePath: staleBundlePath),
        ]
        await env.coordinator.onScanCompleted()

        // Yesterday diff should be non-nil with content (oldOnly was removed,
        // staleApp was added).
        let yd = env.viewModel.latestDiffYesterday
        #expect(yd != nil)
        #expect(yd?.hasContent == true)
        // Stale apps should include the one app whose probe date is 200d old.
        #expect(env.viewModel.staleApps.contains { $0.app.bundleID == "com.example.staleApp" })
    }

    @Test func customStaleThresholdHonored() async throws {
        // Probe returns a 60-day-old date for one app. Default threshold (90)
        // would skip it; a custom 30-day threshold should flag it.
        let bundlePath = URL(fileURLWithPath: "/Applications/SixtyDayApp.app")
        let sixtyDaysAgo = Date(
            timeIntervalSince1970: fixedNow().timeIntervalSince1970 - 60 * 86_400
        )
        let probe = MockLastUsedProbe(fixed: [bundlePath: (sixtyDaysAgo, .spotlight)])
        let env = try await Environment(now: fixedNow, probe: probe, staleThresholdDays: 30)

        env.viewModel.grants = [
            demoGrant(bundleID: "com.example.sixtyDay", bundlePath: bundlePath),
        ]
        await env.coordinator.onScanCompleted()

        #expect(env.viewModel.staleApps.contains { $0.app.bundleID == "com.example.sixtyDay" })
    }

    @Test func changedStaleThresholdAppliesOnNextScan() async throws {
        let path = URL(fileURLWithPath: "/Applications/SixtyDay.app")
        let old = fixedNow().addingTimeInterval(-60 * 86_400)
        let env = try await Environment(
            now: fixedNow,
            probe: MockLastUsedProbe(fixed: [path: (old, .spotlight)])
        )
        env.preferences.staleThresholdDays = 30
        env.viewModel.grants = [
            demoGrant(bundleID: "com.example.sixty", bundlePath: path),
        ]

        await env.coordinator.onScanCompleted()

        #expect(env.viewModel.staleApps.map(\.app.bundleID) == ["com.example.sixty"])
        #expect(env.viewModel.staleThresholdDays == 30)
    }

    @Test func staleAppsFilteredByDismissedStaleAppsStore() async throws {
        // Two stale candidates. One is in the dismissed set → must not appear.
        let keptPath = URL(fileURLWithPath: "/Applications/Kept.app")
        let skippedPath = URL(fileURLWithPath: "/Applications/Skipped.app")
        let old = Date(
            timeIntervalSince1970: fixedNow().timeIntervalSince1970 - 200 * 86_400
        )
        let probe = MockLastUsedProbe(fixed: [
            keptPath: (old, .spotlight),
            skippedPath: (old, .spotlight),
        ])
        let dismissed = DismissedStaleAppStore(
            defaults: UserDefaults(suiteName: "dismissed-stale-\(UUID().uuidString)")!
        )
        dismissed.skipForever(stableKey: "bundle:com.example.skipped")
        let env = try await Environment(now: fixedNow, probe: probe, dismissedStaleApps: dismissed)

        env.viewModel.grants = [
            demoGrant(bundleID: "com.example.kept", bundlePath: keptPath),
            demoGrant(bundleID: "com.example.skipped", bundlePath: skippedPath),
        ]
        await env.coordinator.onScanCompleted()

        let stale = env.viewModel.staleApps
        #expect(stale.contains { $0.app.bundleID == "com.example.kept" })
        #expect(!stale.contains { $0.app.bundleID == "com.example.skipped" })
    }

    @Test func scannerResolvedBundlePathFlowsIntoStaleComputation() async throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ppulse-c2-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let bundleID = "com.example.installed"
        let unresolvedBundleID = "com.example.unresolved"
        let resolvedPath = URL(fileURLWithPath: "/Applications/Installed.app")
        try await makeTCCFixture(
            at: fixture,
            bundleIDs: [bundleID, unresolvedBundleID]
        )
        let scanner = TCCScannerSQLite(
            databaseURLs: [fixture],
            applicationResolver: SnapshotTestApplicationResolver(
                urls: [bundleID: resolvedPath]
            )
        )
        var grants = try await scanner.scan().items
        grants.append(demoGrant(bundleID: ""))
        let old = fixedNow().addingTimeInterval(-200 * 86_400)
        let probe = RecordingLastUsedProbe(
            fixed: [resolvedPath: (old, .spotlight)]
        )
        let env = try await Environment(
            now: fixedNow,
            probe: probe
        )

        env.viewModel.grants = grants
        await env.coordinator.onScanCompleted()

        #expect(grants.first { $0.app.bundleID == bundleID }?.app.bundlePath == resolvedPath)
        #expect(grants.first { $0.app.bundleID == unresolvedBundleID }?.app.bundlePath == nil)
        #expect(env.viewModel.staleApps.map(\.app.bundleID) == [bundleID])
        #expect(await probe.requestedPaths() == [resolvedPath])
    }

    @Test func pathOnlyStaleAppsUseIndependentStableGroupingAndDismissal() async throws {
        let skippedPath = URL(fileURLWithPath: "/Applications/Skipped Path.app")
        let keptPath = URL(fileURLWithPath: "/Applications/Kept Path.app")
        let old = fixedNow().addingTimeInterval(-200 * 86_400)
        let dismissed = DismissedStaleAppStore(
            defaults: UserDefaults(suiteName: "dismissed-path-stale-\(UUID().uuidString)")!
        )
        dismissed.skipForever(stableKey: "path:/Applications/Skipped Path.app")
        let env = try await Environment(
            now: fixedNow,
            probe: MockLastUsedProbe(fixed: [
                skippedPath: (old, .spotlight),
                keptPath: (old, .spotlight),
            ]),
            dismissedStaleApps: dismissed
        )
        env.viewModel.grants = [
            demoGrant(bundleID: "", bundlePath: skippedPath),
            demoGrant(bundleID: "", bundlePath: keptPath),
        ]

        await env.coordinator.onScanCompleted()

        #expect(env.viewModel.staleApps.map(\.app.bundlePath) == [keptPath])
    }

    @Test func customRetentionHonored() async throws {
        // Seed a snapshot 20 days ago. With a 10-day retention, it must be
        // pruned after the next write. We verify by asking the store for the
        // latest snapshot at-or-before a date 15 days ago — after prune the
        // seeded row is gone, so the query returns nil.
        let env = try await Environment(now: fixedNow, snapshotRetentionDays: 10)
        let oldDate = fixedNow().addingTimeInterval(-20 * 86_400)
        _ = try await env.store.writeFullSnapshot(
            grants: [], launchAgents: [], btmItems: [], at: oldDate
        )
        let beforePrune = try await env.store.latestSnapshotID(
            atOrBefore: fixedNow().addingTimeInterval(-15 * 86_400)
        )
        #expect(beforePrune != nil, "Pre-condition: seeded row should be visible")

        env.viewModel.grants = [demoGrant()]
        await env.coordinator.onScanCompleted()

        let afterPrune = try await env.store.latestSnapshotID(
            atOrBefore: fixedNow().addingTimeInterval(-15 * 86_400)
        )
        #expect(afterPrune == nil, "Seeded snapshot should be pruned by 10-day retention")
    }

    @Test func changedRetentionAppliesOnNextScan() async throws {
        let env = try await Environment(now: fixedNow)
        _ = try await env.store.writeFullSnapshot(
            grants: [],
            launchAgents: [],
            btmItems: [],
            at: fixedNow().addingTimeInterval(-20 * 86_400)
        )
        env.preferences.snapshotRetentionDays = 10
        env.viewModel.grants = [demoGrant()]

        await env.coordinator.onScanCompleted()

        let retained = try await env.store.latestSnapshotID(
            atOrBefore: fixedNow().addingTimeInterval(-15 * 86_400)
        )
        #expect(retained == nil)
    }

    @Test func capturesPreferenceProvidersExactlyOncePerScanBoundary() async throws {
        let env = try await Environment(now: fixedNow)
        env.viewModel.grants = [demoGrant()]

        await env.coordinator.onScanCompleted()

        #expect(env.providers.snapshotRetentionReadCount == 1)
        #expect(env.providers.staleThresholdReadCount == 1)

        await env.coordinator.onScanCompleted()

        #expect(env.providers.snapshotRetentionReadCount == 2)
        #expect(env.providers.staleThresholdReadCount == 2)
    }

    @Test func preferenceChangeDuringScanAppliesAtNextBoundary() async throws {
        let path = URL(fileURLWithPath: "/Applications/SixtyDay.app")
        let old = fixedNow().addingTimeInterval(-60 * 86_400)
        let probe = SuspendedLastUsedProbe(result: (old, .spotlight))
        let env = try await Environment(
            now: fixedNow,
            probe: probe,
            staleThresholdDays: 30
        )
        env.viewModel.grants = [
            demoGrant(bundleID: "com.example.sixty", bundlePath: path),
        ]

        let firstScan = Task { @MainActor in
            await env.coordinator.onScanCompleted()
        }
        await probe.waitUntilSuspended()

        #expect(env.providers.snapshotRetentionReadCount == 1)
        #expect(env.providers.staleThresholdReadCount == 1)
        #expect(env.viewModel.staleThresholdDays == 30)
        env.preferences.staleThresholdDays = 90

        await probe.resume()
        await firstScan.value

        #expect(env.viewModel.staleApps.map(\.app.bundleID) == ["com.example.sixty"])
        #expect(env.viewModel.staleThresholdDays == 30)
        #expect(env.providers.staleThresholdReadCount == 1)

        await env.coordinator.onScanCompleted()

        #expect(env.viewModel.staleApps.isEmpty)
        #expect(env.viewModel.staleThresholdDays == 90)
        #expect(env.providers.snapshotRetentionReadCount == 2)
        #expect(env.providers.staleThresholdReadCount == 2)
    }

    @Test func markCurrentSnapshotReviewedClearsBadge() async throws {
        let env = try await Environment(now: fixedNow)
        // Force a state where hasUnreviewedChanges == true.
        env.viewModel.latestSnapshotID = SnapshotID(rawValue: 1)
        env.viewModel.lastReviewedSnapshotID = nil
        env.viewModel.latestDiffYesterday = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 0),
            toID: SnapshotID(rawValue: 1),
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [demoLaunchAgent()], removed: [])
        )
        #expect(env.viewModel.hasUnreviewedChanges)

        env.coordinator.markCurrentSnapshotReviewed()

        #expect(env.viewModel.lastReviewedSnapshotID == SnapshotID(rawValue: 1))
        #expect(!env.viewModel.hasUnreviewedChanges)
        // Persisted to defaults.
        let stored = env.defaults.object(forKey: SnapshotCoordinator.lastReviewedSnapshotIDKey) as? Int64
        #expect(stored == 1)
    }

    @Test func yesterdayDiffUsesCalendarDayBoundaryNotRollingWindow() async throws {
        // Regression for C1. "Now" is early morning today; a snapshot taken
        // yesterday afternoon is only ~18h old, so the old rolling 24h window
        // wrongly excluded it. The calendar-day boundary must include it.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let startOfToday = cal.startOfDay(for: base)
        let nowMorning = startOfToday.addingTimeInterval(8 * 3600)      // today 08:00 UTC
        let yesterdayAfternoon = startOfToday.addingTimeInterval(-10 * 3600) // yesterday 14:00 UTC

        let env = try await Environment(now: { nowMorning }, calendar: cal)
        _ = try await env.store.writeFullSnapshot(
            grants: [demoGrant(bundleID: "com.example.old")],
            launchAgents: [], btmItems: [],
            at: yesterdayAfternoon
        )

        env.viewModel.grants = [demoGrant(bundleID: "com.example.new")]
        await env.coordinator.onScanCompleted()

        #expect(env.viewModel.latestDiffYesterday != nil)
        #expect(env.viewModel.latestDiffYesterday?.hasContent == true)
    }

    @Test func constructingCoordinatorClearsSnapshotStoreUnavailable() async throws {
        // Regression: a successful store (re)open must clear the "unavailable"
        // banner — previously it stuck after a successful Reset All Data.
        let store = try SnapshotStore.inMemory()
        let vm = AppViewModel()
        vm.snapshotStoreUnavailable = true
        _ = SnapshotCoordinator(viewModel: vm, store: store)
        #expect(vm.snapshotStoreUnavailable == false)
    }

    // MARK: - Helpers

    @MainActor
    final class Environment {
        let store: SnapshotStore
        let viewModel: AppViewModel
        let defaults: UserDefaults
        let preferences: PreferencesStore
        let providers: LivePreferenceProviders
        let coordinator: SnapshotCoordinator

        init(
            now: @Sendable @escaping () -> Date,
            probe: any LastUsedProbe = MockLastUsedProbe(),
            calendar: Calendar = Calendar(identifier: .gregorian),
            snapshotRetentionDays: Int = SnapshotCoordinator.defaultSnapshotRetentionDays,
            staleThresholdDays: Int = SnapshotCoordinator.defaultStaleThresholdDays,
            dismissedStaleApps: DismissedStaleAppStore? = nil
        ) async throws {
            self.store = try SnapshotStore.inMemory()
            self.viewModel = AppViewModel(
                tccAvailability: .complete(lastUpdated: now()),
                btmAvailability: .complete(lastUpdated: now()),
                launchAgentAvailability: .complete(lastUpdated: now())
            )
            self.defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
            self.preferences = PreferencesStore(defaults: defaults)
            preferences.snapshotRetentionDays = snapshotRetentionDays
            preferences.staleThresholdDays = staleThresholdDays
            self.providers = LivePreferenceProviders(preferences: preferences)
            self.coordinator = SnapshotCoordinator(
                viewModel: viewModel,
                store: store,
                lastUsedProbe: probe,
                defaults: defaults,
                calendar: calendar,
                now: now,
                snapshotRetentionDays: { [providers] in
                    providers.snapshotRetentionDays()
                },
                staleThresholdDays: { [providers] in
                    providers.staleThresholdDays()
                },
                dismissedStaleApps: dismissedStaleApps
            )
        }

        // Returns the highest snapshot rowid (auto-increment starts at 1), which
        // for a freshly-created in-memory store doubles as a snapshot count.
        func snapshotsCount() async throws -> Int {
            guard let latest = try await store.latestSnapshotID() else { return 0 }
            return Int(latest.rawValue)
        }
    }

    private enum PersistedDomain: CaseIterable {
        case tcc
        case btm
        case launchAgent
    }

    private func setAvailability(
        _ availability: ScanAvailability,
        for domain: PersistedDomain,
        on viewModel: AppViewModel
    ) {
        switch domain {
        case .tcc: viewModel.tccAvailability = availability
        case .btm: viewModel.btmAvailability = availability
        case .launchAgent: viewModel.launchAgentAvailability = availability
        }
    }
}

private struct SnapshotTestApplicationResolver: ApplicationResolving {
    let urls: [String: URL]

    func applicationURL(forBundleIdentifier bundleID: String) async -> URL? {
        urls[bundleID]
    }
}

private func makeTCCFixture(at url: URL, bundleIDs: [String]) async throws {
    let queue = try DatabaseQueue(path: url.path(percentEncoded: false))
    try await queue.write { db in
        try db.execute(sql: """
            CREATE TABLE access (
                service TEXT NOT NULL,
                client TEXT NOT NULL,
                client_type INTEGER NOT NULL,
                auth_value INTEGER NOT NULL,
                last_modified INTEGER NOT NULL,
                indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED'
            )
            """)
        for bundleID in bundleIDs {
            try db.execute(
                sql: """
                    INSERT INTO access
                        (service, client, client_type, auth_value, last_modified)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "kTCCServiceCamera", bundleID, 0, 2, 1_715_000_000,
                ]
            )
        }
    }
}

private actor RecordingLastUsedProbe: LastUsedProbe {
    typealias Result = (date: Date, source: StaleApp.DateSource)

    private let fixed: [URL: Result]
    private var requests: [URL] = []

    init(fixed: [URL: Result]) {
        self.fixed = fixed
    }

    func lastUsedDate(for bundlePath: URL) async -> Result? {
        requests.append(bundlePath)
        return fixed[bundlePath]
    }

    func requestedPaths() -> [URL] {
        requests
    }
}

@MainActor
final class LivePreferenceProviders {
    let preferences: PreferencesStore
    private(set) var snapshotRetentionReadCount = 0
    private(set) var staleThresholdReadCount = 0

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    func snapshotRetentionDays() -> Int {
        snapshotRetentionReadCount += 1
        return preferences.snapshotRetentionDays
    }

    func staleThresholdDays() -> Int {
        staleThresholdReadCount += 1
        return preferences.staleThresholdDays
    }
}

private actor SuspendedLastUsedProbe: LastUsedProbe {
    typealias Result = (date: Date, source: StaleApp.DateSource)

    private let result: Result
    private var shouldSuspend = true
    private var probeContinuation: CheckedContinuation<Result?, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(result: Result) {
        self.result = result
    }

    func lastUsedDate(for bundlePath: URL) async -> Result? {
        guard shouldSuspend else { return result }
        shouldSuspend = false

        return await withCheckedContinuation { continuation in
            probeContinuation = continuation
            let waiters = suspensionWaiters
            suspensionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilSuspended() async {
        guard probeContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resume() {
        let continuation = probeContinuation
        probeContinuation = nil
        continuation?.resume(returning: result)
    }
}

@Sendable
private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 1_700_000_000)
}

private func demoGrant(
    bundleID: String = "com.example.demo",
    bundlePath: URL? = nil
) -> PermissionGrant {
    PermissionGrant(
        service: .microphone,
        app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: bundlePath),
        lastModified: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func demoLaunchAgent(label: String = "com.example.demo") -> LaunchAgentItem {
    LaunchAgentItem(
        label: label,
        sourceDirectory: .userLaunchAgents,
        programPath: "/usr/local/bin/demo",
        programArguments: [],
        runAtLoad: true,
        keepAlive: false
    )
}
