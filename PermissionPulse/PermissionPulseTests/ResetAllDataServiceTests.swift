import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ResetAllDataServiceTests {
    @Test func resetCascadesThroughLivePersistedAndNotificationState() async throws {
        let env = try Environment()
        defer { env.cleanUp() }

        env.preferencesStore.snapshotRetentionDays = 120
        env.preferencesStore.staleThresholdDays = 180
        env.preferencesStore.digestEnabled = true
        env.preferencesStore.digestWeekday = 6
        env.preferencesStore.digestHour = 17
        env.preferencesStore.digestMinute = 45
        env.dismissedDiffEntries.dismissForever(key: "diff-key")
        env.dismissedStaleApps.skipForever(stableKey: "bundle:com.example.stale")
        _ = await env.weeklyDigestCoordinator.reconcileSchedule()
        try await env.scheduler.scheduleOneShot(
            identifier: "\(WeeklyDigestCoordinator.testIdentifierPrefix).seed",
            after: 5,
            title: "Test",
            body: "Test"
        )
        try Data("main".utf8).write(to: env.dbURL)
        try Data("wal".utf8).write(to: env.walURL)
        try Data("shm".utf8).write(to: env.shmURL)

        let result = await env.service.reset()

        #expect(result == .completed(scanSucceeded: true))
        #expect(env.preferencesStore.snapshotRetentionDays == 90)
        #expect(env.preferencesStore.staleThresholdDays == 90)
        #expect(env.preferencesStore.digestEnabled == false)
        #expect(env.preferencesStore.digestWeekday == 2)
        #expect(env.preferencesStore.digestHour == 9)
        #expect(env.preferencesStore.digestMinute == 0)
        #expect(env.dismissedDiffEntries.allEntries().isEmpty)
        #expect(env.dismissedStaleApps.allStableKeys().isEmpty)
        #expect(await env.scheduler.pendingIdentifiers().isEmpty)
        #expect(env.state.releaseCount == 1)
        #expect(env.state.reinitCount == 1)
        #expect(env.state.rescanCount == 1)
        #expect(FileManager.default.fileExists(atPath: env.dbURL.path))
        #expect(!FileManager.default.fileExists(atPath: env.walURL.path))
        #expect(!FileManager.default.fileExists(atPath: env.shmURL.path))
    }

    @Test func deletionFailureReportsPhaseAndStopsBeforeReinitAndRescan() async throws {
        let fileManager = ThrowingResetFileManager(
            failingSuffix: "snapshots.db",
            message: "injected removal failure"
        )
        let env = try Environment(fileManager: fileManager)
        defer { env.cleanUp() }
        try Data("main".utf8).write(to: env.dbURL)

        let result = await env.service.reset()

        #expect(result == .failed(
            phase: .deleteHistory,
            message: "injected removal failure"
        ))
        #expect(env.state.releaseCount == 1)
        #expect(env.state.reinitCount == 0)
        #expect(env.state.rescanCount == 0)
    }

    @Test(arguments: MissingFileErrorKind.allCases)
    func fileDisappearingBeforeRemovalIsIdempotent(
        errorKind: MissingFileErrorKind
    ) async throws {
        let fileManager = MissingOnRemoveFileManager(errorKind: errorKind)
        let env = try Environment(fileManager: fileManager)
        defer { env.cleanUp() }
        try Data("main".utf8).write(to: env.dbURL)
        try Data("wal".utf8).write(to: env.walURL)
        try Data("shm".utf8).write(to: env.shmURL)

        let result = await env.service.reset()

        #expect(result == .completed(scanSucceeded: true))
        #expect(fileManager.removedURLs.map(\.lastPathComponent) == [
            "snapshots.db",
            "snapshots.db-wal",
            "snapshots.db-shm",
        ])
        #expect(env.state.reinitCount == 1)
        #expect(env.state.rescanCount == 1)
    }

    @Test(arguments: ["-wal", "-shm"])
    func sidecarDeletionFailureStopsRemainingPhases(failingSuffix: String) async throws {
        let fileManager = ThrowingResetFileManager(
            failingSuffix: failingSuffix,
            message: "injected \(failingSuffix) failure"
        )
        let env = try Environment(fileManager: fileManager)
        defer { env.cleanUp() }
        env.preferencesStore.digestEnabled = true
        try Data("main".utf8).write(to: env.dbURL)
        try Data("wal".utf8).write(to: env.walURL)
        try Data("shm".utf8).write(to: env.shmURL)

        let result = await env.service.reset()

        #expect(result == .failed(
            phase: .deleteHistory,
            message: "injected \(failingSuffix) failure"
        ))
        #expect(env.preferencesStore.digestEnabled == true)
        #expect(env.state.reinitCount == 0)
        #expect(env.state.rescanCount == 0)
        if failingSuffix == "-wal" {
            #expect(FileManager.default.fileExists(atPath: env.shmURL.path))
        }
    }

    @Test func scanFailureIsACompletedResetOutcome() async throws {
        let env = try Environment(scanSucceeded: false)
        defer { env.cleanUp() }

        let result = await env.service.reset()

        #expect(result == .completed(scanSucceeded: false))
        #expect(env.state.releaseCount == 1)
        #expect(env.state.reinitCount == 1)
        #expect(env.state.rescanCount == 1)
    }

    @Test func notificationCancellationUsesOnlyApprovedPrefixes() async throws {
        let env = try Environment()
        defer { env.cleanUp() }
        try await env.scheduler.scheduleWeekly(
            identifier: WeeklyDigestCoordinator.weeklyIdentifier,
            weekday: 2,
            hour: 9,
            minute: 0,
            title: "Weekly",
            body: "Weekly"
        )
        try await env.scheduler.scheduleOneShot(
            identifier: "\(WeeklyDigestCoordinator.testIdentifierPrefix).seed",
            after: 5,
            title: "Test",
            body: "Test"
        )
        try await env.scheduler.scheduleOneShot(
            identifier: "com.example.unrelated",
            after: 5,
            title: "Other",
            body: "Other"
        )

        _ = await env.service.reset()

        #expect(await env.scheduler.pendingIdentifiers() == ["com.example.unrelated"])
    }

    @Test func phasesRunInOrderAndPresentationStateClearsBeforeRescan() async throws {
        let trace = LockedTrace()
        let scheduler = TracingWeeklyDigestScheduler(trace: trace)
        let defaultsSuite = "reset-order-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let preferences = PreferencesStore(defaults: defaults)
        let dismissedDiffEntries = DismissedDiffEntryStore(defaults: defaults)
        let dismissedStaleApps = DismissedStaleAppStore(defaults: defaults)
        let viewModel = AppViewModel()
        let coordinator = WeeklyDigestCoordinator(
            viewModel: viewModel,
            preferencesStore: preferences,
            scheduler: scheduler
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reset-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dbURL = directory.appendingPathComponent("snapshots.db")
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: dbURL.path + "-shm")
        try Data("main".utf8).write(to: dbURL)
        try Data("wal".utf8).write(to: walURL)
        try Data("shm".utf8).write(to: shmURL)
        try await seedPresentationState(viewModel)
        preferences.digestEnabled = true
        dismissedDiffEntries.dismissForever(key: "diff-key")
        dismissedStaleApps.skipForever(stableKey: "bundle:com.example.stale")
        defaults.set("seed", forKey: "com.wallymagill.permissionpulse.seed")

        let service = ResetAllDataService(
            viewModel: viewModel,
            snapshotPathURL: dbURL,
            releaseSnapshotStore: { trace.append("release") },
            onSnapshotStoreReinit: { _ in
                #expect(preferences.digestEnabled == false)
                #expect(dismissedDiffEntries.allEntries().isEmpty)
                #expect(dismissedStaleApps.allStableKeys().isEmpty)
                #expect(defaults.object(forKey: "com.wallymagill.permissionpulse.seed") == nil)
                trace.append("recreate")
            },
            weeklyDigestCoordinator: coordinator,
            preferencesStore: preferences,
            dismissedDiffEntries: dismissedDiffEntries,
            dismissedStaleApps: dismissedStaleApps,
            fileManager: TracingResetFileManager(trace: trace),
            defaults: defaults,
            rescan: {
                expectPresentationStateCleared(viewModel)
                trace.append("rescan")
                return true
            }
        )

        let result = await service.reset()

        #expect(result == .completed(scanSucceeded: true))
        #expect(trace.values == [
            "cancel:\(WeeklyDigestCoordinator.identifierPrefix)",
            "cancel:\(WeeklyDigestCoordinator.testIdentifierPrefix)",
            "release",
            "delete:snapshots.db",
            "delete:snapshots.db-wal",
            "delete:snapshots.db-shm",
            "recreate",
            "rescan",
            "cancel:\(WeeklyDigestCoordinator.identifierPrefix)",
        ])
    }

    @Test func removesSnapshotsDBAndReInitsStore() async throws {
        let env = try Environment()
        defer { env.cleanUp() }

        try Data("seed".utf8).write(to: env.dbURL)
        #expect(FileManager.default.fileExists(atPath: env.dbURL.path))

        let result = await env.service.reset()

        // SnapshotStore init re-creates the file (empty SQLite).
        #expect(FileManager.default.fileExists(atPath: env.dbURL.path))
        #expect(env.state.reinitCount == 1)
        #expect(result == .completed(scanSucceeded: true))
    }

    @Test func removesAllPPDefaultsKeysPreservingNonPPKeys() async throws {
        let env = try Environment()
        defer { env.cleanUp() }
        env.defaults.set("a", forKey: "com.wallymagill.permissionpulse.hasSeenWelcome")
        env.defaults.set("b", forKey: "com.wallymagill.permissionpulse.lastSnapshotDate")
        env.defaults.set("preserve", forKey: "NSWindow Frame detail-AppWindow-1")
        env.defaults.set("preserve", forKey: "NSStatusItem Preferred Position Item-0")

        await env.service.reset()

        #expect(env.defaults.object(forKey: "com.wallymagill.permissionpulse.hasSeenWelcome") == nil)
        #expect(env.defaults.object(forKey: "com.wallymagill.permissionpulse.lastSnapshotDate") == nil)
        #expect(env.defaults.string(forKey: "NSWindow Frame detail-AppWindow-1") == "preserve")
        #expect(env.defaults.string(forKey: "NSStatusItem Preferred Position Item-0") == "preserve")
    }

    @Test(arguments: ResetDefaultsFailureMode.allCases)
    func defaultsClearingFailureStopsBeforeRecreateAndRescan(
        failureMode: ResetDefaultsFailureMode
    ) async throws {
        let resetDefaults = FailingResetDefaults(mode: failureMode)
        let env = try Environment(resetDefaults: resetDefaults)
        defer { env.cleanUp() }

        let result = await env.service.reset()

        guard case .failed(phase: .clearDefaults, message: let message) = result else {
            Issue.record("Expected clear-defaults failure, got \(result)")
            return
        }
        #expect(!message.isEmpty)
        #expect(resetDefaults.removedKeys == ["com.wallymagill.permissionpulse.seed"])
        #expect(resetDefaults.value(forKey: "unrelated.key") == "preserve")
        #expect(env.state.reinitCount == 0)
        #expect(env.state.rescanCount == 0)
    }

    @Test func cancelsPendingDigestNotifications() async throws {
        let env = try Environment()
        defer { env.cleanUp() }
        try await env.scheduler.scheduleWeekly(
            identifier: WeeklyDigestCoordinator.weeklyIdentifier,
            weekday: 2, hour: 9, minute: 0,
            title: "T", body: "B"
        )
        let beforePending = await env.scheduler.pendingIdentifiers()
        #expect(beforePending.count == 1)

        await env.service.reset()

        let afterPending = await env.scheduler.pendingIdentifiers()
        #expect(afterPending.isEmpty)
    }

    @Test func resetReportsReinitSuccess() async throws {
        let env = try Environment()
        defer { env.cleanUp() }
        let result = await env.service.reset()
        #expect(result == .completed(scanSucceeded: true))
    }

    @Test func idempotentOnSecondCallWithEmptyState() async throws {
        let env = try Environment()
        defer { env.cleanUp() }
        let first = await env.service.reset()
        let second = await env.service.reset()
        #expect(first == .completed(scanSucceeded: true))
        #expect(second == .completed(scanSucceeded: true))
        #expect(env.state.reinitCount == 2, "Re-init runs each call even when DB absent")
    }

    @Test func overlappingResetIsRejectedBeforeAnySecondPhaseSideEffects() async throws {
        let scheduler = SuspendingWeeklyDigestScheduler()
        let env = try Environment(weeklyDigestScheduler: scheduler)
        defer { env.cleanUp() }

        let firstTask = Task { await env.service.reset() }
        await scheduler.waitUntilFirstCancellationSuspends()

        let second = await env.service.reset()

        #expect(second == .failed(
            phase: .cancelNotifications,
            message: "Reset All Data is already in progress."
        ))
        #expect(await scheduler.cancellationCallCount == 1)
        #expect(env.state.releaseCount == 0)
        #expect(env.state.reinitCount == 0)
        #expect(env.state.rescanCount == 0)

        await scheduler.resumeFirstCancellation()
        let first = await firstTask.value
        #expect(first == .completed(scanSucceeded: true))
        #expect(env.state.releaseCount == 1)
        #expect(env.state.reinitCount == 1)
        #expect(env.state.rescanCount == 1)
    }

    @Test func resetReportsFailureWhenStoreCannotReinit() async throws {
        // Make the parent of the snapshot path a regular file so SnapshotStore
        // re-init must fail (you can't create a file inside a file).
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pp-reset-fail-\(UUID().uuidString)")
        try Data().write(to: tmp)                       // `tmp` is now a regular FILE
        defer { try? FileManager.default.removeItem(at: tmp) }
        let badPath = tmp.appendingPathComponent("snapshots.db")  // parent is a file

        var reinitCalled = false
        var rescanCalled = false
        let env = try Environment()
        defer { env.cleanUp() }
        let service = ResetAllDataService(
            viewModel: env.viewModel,
            snapshotPathURL: badPath,
            releaseSnapshotStore: { },
            onSnapshotStoreReinit: { _ in reinitCalled = true },
            weeklyDigestCoordinator: env.weeklyDigestCoordinator,
            preferencesStore: env.preferencesStore,
            dismissedDiffEntries: env.dismissedDiffEntries,
            dismissedStaleApps: env.dismissedStaleApps,
            fileManager: MissingOnRemoveFileManager(errorKind: .cocoa),
            defaults: env.defaults,
            rescan: {
                rescanCalled = true
                return true
            }
        )
        let result = await service.reset()
        guard case .failed(phase: .recreateHistory, message: let message) = result else {
            Issue.record("Expected recreation failure, got \(result)")
            return
        }
        #expect(!message.isEmpty)
        #expect(reinitCalled == false)
        #expect(rescanCalled == false)
    }

    // MARK: - Env

    @MainActor
    final class ResetState {
        var releaseCount = 0
        var reinitCount: Int = 0
        var rescanCount: Int = 0
    }

    @MainActor
    final class Environment {
        let viewModel: AppViewModel
        let preferencesStore: PreferencesStore
        let dismissedDiffEntries: DismissedDiffEntryStore
        let dismissedStaleApps: DismissedStaleAppStore
        let scheduler: any WeeklyDigestScheduler
        let weeklyDigestCoordinator: WeeklyDigestCoordinator
        let defaults: UserDefaults
        let dbURL: URL
        var walURL: URL { URL(fileURLWithPath: dbURL.path + "-wal") }
        var shmURL: URL { URL(fileURLWithPath: dbURL.path + "-shm") }
        let directoryURL: URL
        let defaultsSuiteName: String
        let state = ResetState()
        let service: ResetAllDataService

        init(
            fileManager: any ResetFileManaging = FileManager.default,
            resetDefaults: (any ResetDefaultsManaging)? = nil,
            weeklyDigestScheduler: (any WeeklyDigestScheduler)? = nil,
            scanSucceeded: Bool = true
        ) throws {
            self.viewModel = AppViewModel()
            self.defaultsSuiteName = "reset-test-\(UUID().uuidString)"
            self.defaults = UserDefaults(suiteName: defaultsSuiteName)!
            self.preferencesStore = PreferencesStore(defaults: defaults)
            self.dismissedDiffEntries = DismissedDiffEntryStore(defaults: defaults)
            self.dismissedStaleApps = DismissedStaleAppStore(defaults: defaults)
            let scheduler = weeklyDigestScheduler
                ?? MockWeeklyDigestScheduler(initialStatus: .authorized)
            self.scheduler = scheduler
            self.weeklyDigestCoordinator = WeeklyDigestCoordinator(
                viewModel: viewModel,
                preferencesStore: preferencesStore,
                scheduler: scheduler
            )

            self.directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("reset-svc-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            self.dbURL = directoryURL.appendingPathComponent("snapshots.db")

            let state = state
            self.service = ResetAllDataService(
                viewModel: viewModel,
                snapshotPathURL: dbURL,
                releaseSnapshotStore: { state.releaseCount += 1 },
                onSnapshotStoreReinit: { _ in state.reinitCount += 1 },
                weeklyDigestCoordinator: weeklyDigestCoordinator,
                preferencesStore: preferencesStore,
                dismissedDiffEntries: dismissedDiffEntries,
                dismissedStaleApps: dismissedStaleApps,
                fileManager: fileManager,
                defaults: resetDefaults ?? defaults,
                rescan: {
                    state.rescanCount += 1
                    return scanSucceeded
                }
            )
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }
}

private struct InjectedResetError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum MissingFileErrorKind: CaseIterable, Sendable {
    case cocoa
    case posix
}

enum ResetDefaultsFailureMode: CaseIterable, Sendable {
    case retained
    case throwing
}

@MainActor
private final class FailingResetDefaults: ResetDefaultsManaging {
    private let mode: ResetDefaultsFailureMode
    private var values = [
        "com.wallymagill.permissionpulse.seed": "delete",
        "unrelated.key": "preserve",
    ]
    private(set) var removedKeys: [String] = []

    init(mode: ResetDefaultsFailureMode) {
        self.mode = mode
    }

    func resetKeys() -> [String] {
        Array(values.keys)
    }

    func removeResetValue(forKey key: String) throws {
        removedKeys.append(key)
        switch mode {
        case .retained:
            return
        case .throwing:
            throw InjectedResetError(message: "injected defaults removal failure")
        }
    }

    func containsResetValue(forKey key: String) -> Bool {
        values[key] != nil
    }

    func value(forKey key: String) -> String? {
        values[key]
    }
}

private final class MissingOnRemoveFileManager: ResetFileManaging, @unchecked Sendable {
    private let lock = NSLock()
    private let errorKind: MissingFileErrorKind
    private var storedRemovedURLs: [URL] = []

    init(errorKind: MissingFileErrorKind) {
        self.errorKind = errorKind
    }

    var removedURLs: [URL] {
        lock.withLock { storedRemovedURLs }
    }

    func removeItem(at url: URL) throws {
        lock.withLock { storedRemovedURLs.append(url) }
        // Simulate another process removing the file after this call begins.
        try? FileManager.default.removeItem(at: url)
        switch errorKind {
        case .cocoa:
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        case .posix:
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        }
    }
}

private final class ThrowingResetFileManager: ResetFileManaging, @unchecked Sendable {
    private let failingSuffix: String
    private let message: String

    init(failingSuffix: String, message: String) {
        self.failingSuffix = failingSuffix
        self.message = message
    }

    func removeItem(at url: URL) throws {
        if url.path.hasSuffix(failingSuffix) {
            throw InjectedResetError(message: message)
        }
        try FileManager.default.removeItem(at: url)
    }
}

private final class LockedTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct TracingResetFileManager: ResetFileManaging {
    let trace: LockedTrace

    func removeItem(at url: URL) throws {
        trace.append("delete:\(url.lastPathComponent)")
        try FileManager.default.removeItem(at: url)
    }
}

private actor TracingWeeklyDigestScheduler: WeeklyDigestScheduler {
    let trace: LockedTrace

    init(trace: LockedTrace) {
        self.trace = trace
    }

    func currentAuthorizationStatus() async -> DigestAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> DigestAuthorizationStatus { .authorized }
    func scheduleWeekly(
        identifier: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async throws {}
    func scheduleOneShot(
        identifier: String,
        after seconds: TimeInterval,
        title: String,
        body: String
    ) async throws {}
    func cancelAll(matchingPrefix prefix: String) async {
        trace.append("cancel:\(prefix)")
    }
    func pendingIdentifiers() async -> [String] { [] }
    func nextFireDate(for identifier: String) async -> Date? { nil }
}

private actor SuspendingWeeklyDigestScheduler: WeeklyDigestScheduler {
    private var firstCancellationContinuation: CheckedContinuation<Void, Never>?
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstCancellationIsSuspended = false
    private(set) var cancellationCallCount = 0

    func currentAuthorizationStatus() async -> DigestAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> DigestAuthorizationStatus { .authorized }
    func scheduleWeekly(
        identifier: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        title: String,
        body: String
    ) async throws {}
    func scheduleOneShot(
        identifier: String,
        after seconds: TimeInterval,
        title: String,
        body: String
    ) async throws {}
    func cancelAll(matchingPrefix prefix: String) async {
        cancellationCallCount += 1
        guard cancellationCallCount == 1 else { return }
        firstCancellationIsSuspended = true
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            firstCancellationContinuation = continuation
        }
    }
    func pendingIdentifiers() async -> [String] { [] }
    func nextFireDate(for identifier: String) async -> Date? { nil }

    func waitUntilFirstCancellationSuspends() async {
        guard !firstCancellationIsSuspended else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters.append(continuation)
        }
    }

    func resumeFirstCancellation() {
        firstCancellationContinuation?.resume()
        firstCancellationContinuation = nil
    }
}

@MainActor
private func seedPresentationState(_ viewModel: AppViewModel) async throws {
    let grants = try await MockTCCScanner().scan().items
    let launchAgents = try await MockLaunchAgentScanner().scan().items
    let btmItems = try await MockBTMScanner().scan().items
    viewModel.grants = grants
    viewModel.launchAgents = launchAgents
    viewModel.btmItems = btmItems
    viewModel.tccScanError = .permissionDenied(reason: "tcc")
    viewModel.btmScanError = .schemaMismatch(detail: "btm")
    viewModel.launchAgentScanError = .temporarilyUnavailable(reason: "launch")
    viewModel.latestSnapshotID = SnapshotID(rawValue: 2)
    viewModel.lastReviewedSnapshotID = SnapshotID(rawValue: 1)
    let diff = SnapshotDiffs(
        fromID: SnapshotID(rawValue: 1),
        toID: SnapshotID(rawValue: 2),
        tcc: TCCGrantsDiff(added: grants, removed: []),
        btm: BTMItemsDiff(added: btmItems, removed: []),
        launchAgents: LaunchAgentsDiff(added: launchAgents, removed: [])
    )
    viewModel.latestDiffYesterday = diff
    viewModel.latestDiffWeek = diff
    viewModel.staleApps = [StaleApp(
        app: grants[0].app,
        lastUsedDate: Date(timeIntervalSince1970: 1_700_000_000),
        dateSource: .spotlight,
        daysSinceUsed: 100,
        grantedServices: [grants[0].service]
    )]
    viewModel.pendingRoute = .recentChanges
    viewModel.lastScanDate = Date(timeIntervalSince1970: 1_700_000_000)
    viewModel.staleThresholdDays = 180
    viewModel.snapshotStoreUnavailable = true
    viewModel.diffUnavailable = true
}

@MainActor
private func expectPresentationStateCleared(_ viewModel: AppViewModel) {
    #expect(viewModel.grants.isEmpty)
    #expect(viewModel.launchAgents.isEmpty)
    #expect(viewModel.btmItems.isEmpty)
    #expect(viewModel.tccScanError == nil)
    #expect(viewModel.btmScanError == nil)
    #expect(viewModel.launchAgentScanError == nil)
    #expect(viewModel.latestSnapshotID == nil)
    #expect(viewModel.lastReviewedSnapshotID == nil)
    #expect(viewModel.latestDiffYesterday == nil)
    #expect(viewModel.latestDiffWeek == nil)
    #expect(viewModel.staleApps.isEmpty)
    #expect(viewModel.pendingRoute == nil)
    #expect(viewModel.lastScanDate == nil)
    #expect(viewModel.staleThresholdDays == 90)
    #expect(viewModel.snapshotStoreUnavailable == false)
    #expect(viewModel.diffUnavailable == false)
}
