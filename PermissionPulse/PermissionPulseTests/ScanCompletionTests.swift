import AppKit
import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct ScanCompletionTests {
    @Test func scanThatChangesTheWeekDiffRefreshesThePendingDigestBody() async throws {
        let env = try ScanEnvironment()
        defer { env.cleanUp() }
        // An empty, fully captured snapshot from before the 7-day cutoff is
        // the week baseline the scan's mock results are compared against.
        _ = try await env.store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [], coverage: .allComplete,
            at: Date().addingTimeInterval(-9 * 86_400)
        )
        env.delegate.preferencesStore.digestEnabled = true
        _ = await env.delegate.weeklyDigestCoordinator.reconcileSchedule()
        let before = await env.scheduler.lastScheduledWeeklyBody()

        await env.delegate.rescan()

        let after = await env.scheduler.lastScheduledWeeklyBody()
        #expect(before == "History is less than a week old, so there's nothing to compare yet.")
        #expect(after != before)
        #expect(after?.hasSuffix("in the last week.") == true)
        #expect(await env.scheduler.pendingIdentifiers() == [WeeklyDigestCoordinator.weeklyIdentifier])
    }

    @Test func changeAlertNamesTheChangesSinceThePreviousSnapshot() async throws {
        let env = try ScanEnvironment()
        defer { env.cleanUp() }
        _ = try await env.store.writeSnapshot(
            grants: [], launchAgents: [], btmItems: [], coverage: .allComplete,
            at: Date().addingTimeInterval(-3_600)
        )
        env.delegate.preferencesStore.changeAlertsEnabled = true

        await env.delegate.rescan()

        let alerts = await env.scheduler.oneShots(withPrefix: ChangeAlertCoordinator.identifierPrefix)
        #expect(alerts.map(\.identifier) == [ChangeAlertCoordinator.changesIdentifier])
        #expect(alerts.first?.title == "Permission Pulse: something changed")
        let body = try #require(alerts.first?.body)
        #expect(body.contains(" changes: "))
        #expect(body.contains(" other change"))
    }

    @Test func firstSnapshotEverPostsNoChangeAlert() async throws {
        let env = try ScanEnvironment()
        defer { env.cleanUp() }
        env.delegate.preferencesStore.changeAlertsEnabled = true

        await env.delegate.rescan()

        #expect(env.delegate.viewModel.latestSnapshotID != nil)
        #expect(await env.scheduler.oneShots(withPrefix: ChangeAlertCoordinator.identifierPrefix).isEmpty)
    }
}

@MainActor
final class ScanEnvironment {
    let directory: URL
    let store: SnapshotStore
    let scheduler: MockWeeklyDigestScheduler
    let delegate: AppDelegate

    init(
        status: DigestAuthorizationStatus = .authorized,
        appVersion: AppVersion = .running,
        fullDiskAccessPromptPresenter: (@MainActor (FullDiskAccessLoss) -> Void)? = { _ in }
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-environment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try SnapshotStore(
            path: directory.appendingPathComponent("snapshots.db").path(percentEncoded: false)
        )
        scheduler = MockWeeklyDigestScheduler(initialStatus: status)
        delegate = AppDelegate(
            runtimeEnvironment: AppRuntimeEnvironment(environment: ["PERMISSION_PULSE_TEST_MODE": "1"]),
            weeklyDigestScheduler: scheduler,
            appVersion: appVersion,
            fullDiskAccessPromptPresenter: fullDiskAccessPromptPresenter
        )
        delegate.installSnapshotRuntime(store)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        if let suiteName = delegate.runtimeDefaultsSuiteName {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
    }
}

extension MockWeeklyDigestScheduler {
    func lastScheduledWeeklyBody() -> String? {
        recorded.reversed().lazy.compactMap { action -> String? in
            guard case .scheduled(_, _, _, _, _, let body) = action else { return nil }
            return body
        }.first
    }

    func oneShots(withPrefix prefix: String) -> [(identifier: String, title: String, body: String)] {
        recorded.compactMap { action in
            guard case .scheduledOneShot(let identifier, _, let title, let body) = action,
                  identifier.hasPrefix(prefix) else { return nil }
            return (identifier, title, body)
        }
    }
}

@Suite @MainActor struct ReopenTests {
    @Test func reopenAsksTheTrampolineForTheDetailWindowOnOverview() throws {
        let env = try ScanEnvironment()
        defer { env.cleanUp() }
        env.delegate.viewModel.pendingRoute = .recentChanges

        let handledByDefault = env.delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)

        #expect(!handledByDefault)
        #expect(env.delegate.viewModel.windowToOpen == "detail")
        #expect(env.delegate.viewModel.pendingRoute == .overview)
    }

    @Test func reopenOnlyBringsAnOpenDetailWindowForwardAndDropsAStaleRoute() throws {
        let env = try ScanEnvironment()
        defer { env.cleanUp() }
        env.delegate.viewModel.isDetailWindowOpen = true
        env.delegate.viewModel.pendingRoute = .recentChanges

        _ = env.delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)

        #expect(env.delegate.viewModel.windowToOpen == "detail")
        #expect(env.delegate.viewModel.pendingRoute == nil)
    }

    @Test func clickingAChangeAlertOpensRecentChanges() throws {
        let env = try ScanEnvironment()
        defer { env.cleanUp() }

        env.delegate.openNotification(identifier: ChangeAlertCoordinator.changesIdentifier)

        #expect(env.delegate.viewModel.windowToOpen == "detail")
        #expect(env.delegate.viewModel.pendingRoute == .recentChanges)
    }
}

@Suite @MainActor struct NotificationDestinationTests {
    @Test func eachNotificationOpensItsOwnPlace() {
        #expect(NotificationDestination.forRequest(ChangeAlertCoordinator.changesIdentifier) == .detail(.recentChanges))
        #expect(NotificationDestination.forRequest(ChangeAlertCoordinator.fullDiskAccessIdentifier) == .fullDiskAccessRecovery)
        #expect(NotificationDestination.forRequest(WeeklyDigestCoordinator.weeklyIdentifier) == .detail(.recentChangesLastSevenDays))
        #expect(NotificationDestination.forRequest(WeeklyDigestCoordinator.overdueIdentifier) == .detail(.recentChangesLastSevenDays))
        #expect(NotificationDestination.forRequest("\(WeeklyDigestCoordinator.testIdentifierPrefix).ABC") == nil)
    }
}
