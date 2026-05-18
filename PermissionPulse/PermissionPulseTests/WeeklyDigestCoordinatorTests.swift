import Foundation
import Testing
import PermissionsCore
import PermissionsScanners
import PermissionsStore
import PermissionsUI
@testable import PermissionPulse

@Suite @MainActor struct WeeklyDigestCoordinatorTests {
    @Test func reconcileScheduleWhenDisabledCancelsAndDoesNotSchedule() async throws {
        let env = makeEnv(digestEnabled: false, status: .authorized)
        await env.coordinator.reconcileSchedule()

        let actions = await env.scheduler.recorded
        #expect(actions.contains { if case .canceledAll = $0 { true } else { false } })
        #expect(!actions.contains { if case .scheduled = $0 { true } else { false } })
    }

    @Test func reconcileScheduleWhenEnabledAndAuthorizedSchedulesOnce() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        await env.coordinator.reconcileSchedule()

        let pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.count == 1)
        #expect(pending.first == WeeklyDigestCoordinator.weeklyIdentifier)
    }

    @Test func reconcileScheduleCalledTwiceIsIdempotent() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        await env.coordinator.reconcileSchedule()
        await env.coordinator.reconcileSchedule()

        let pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.count == 1, "Expected exactly one pending after double reconcile")
    }

    @Test func handleAuthorizationToggleOnWhenDeniedReturnsDeniedHint() async throws {
        let env = makeEnv(digestEnabled: false, status: .denied)
        let result = await env.coordinator.handleAuthorizationToggle(turnOn: true)
        #expect(result == .deniedNeedsSystemSettings)
    }

    @Test func handleAuthorizationToggleOnWhenAuthorizedSchedules() async throws {
        let env = makeEnv(digestEnabled: false, status: .authorized)
        env.preferencesStore.digestEnabled = true
        let result = await env.coordinator.handleAuthorizationToggle(turnOn: true)
        #expect(result == .scheduled)
        let pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.count == 1)
    }

    @Test func composeEmptyWeekReturnsHeartbeatString() {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let composed = env.coordinator.composeDigestBody(diff: nil)
        #expect(composed.body == String(localized: "No changes in the last week."))
    }

    @Test func composeMixedDiffMentionsAddedAndRemoved() {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 1),
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(added: [demoGrant()], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [demoLaunchAgent()])
        )
        let composed = env.coordinator.composeDigestBody(diff: diff)
        #expect(composed.body.contains("1 added"))
        #expect(composed.body.contains("1 removed"))
    }

    @Test func composeAddedOnlyOmitsRemovedAndChanged() {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 1),
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(added: [demoGrant(), demoGrant(bundleID: "com.b")], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [])
        )
        let composed = env.coordinator.composeDigestBody(diff: diff)
        #expect(composed.body.contains("2 added"))
        #expect(!composed.body.contains("removed"))
        #expect(!composed.body.contains("changed"))
    }

    @Test func composeRemovedOnlyOmitsAddedAndChanged() {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 1),
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(added: [], removed: [demoGrant()]),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [])
        )
        let composed = env.coordinator.composeDigestBody(diff: diff)
        #expect(composed.body.contains("1 removed"))
        #expect(!composed.body.contains("added"))
        #expect(!composed.body.contains("changed"))
    }

    @Test func handleAuthorizationToggleOffCancelsPending() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        env.preferencesStore.digestEnabled = true
        await env.coordinator.reconcileSchedule()
        var pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.count == 1)

        let result = await env.coordinator.handleAuthorizationToggle(turnOn: false)
        #expect(result == .disabled)

        pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.isEmpty)
    }

    @Test func sendTestNotificationWhenAuthorizedSchedulesOneShot() async throws {
        let env = makeEnv(digestEnabled: false, status: .authorized)
        let result = await env.coordinator.sendTestNotification(after: 5)
        if case .scheduled(let seconds) = result {
            #expect(seconds == 5)
        } else {
            Issue.record("Expected .scheduled, got \(result)")
        }
        let pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.contains(where: { $0.hasPrefix(WeeklyDigestCoordinator.testIdentifierPrefix) }))
    }

    @Test func sendTestNotificationWhenDeniedReturnsNotAuthorized() async throws {
        let env = makeEnv(digestEnabled: false, status: .denied)
        let result = await env.coordinator.sendTestNotification(after: 5)
        #expect(result == .notAuthorized)
        let pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.isEmpty)
    }

    @Test func nextWeeklyFireDateReturnsPendingDate() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        await env.coordinator.reconcileSchedule()
        let date = await env.coordinator.nextWeeklyFireDate()
        #expect(date != nil)
    }

    @Test func nextWeeklyFireDateNilWhenNothingPending() async throws {
        let env = makeEnv(digestEnabled: false, status: .authorized)
        let date = await env.coordinator.nextWeeklyFireDate()
        #expect(date == nil)
    }

    // MARK: - Env

    @MainActor
    final class Environment {
        let viewModel: AppViewModel
        let preferencesStore: PreferencesStore
        let scheduler: MockWeeklyDigestScheduler
        let coordinator: WeeklyDigestCoordinator

        init(digestEnabled: Bool, status: DigestAuthorizationStatus) {
            self.viewModel = AppViewModel()
            let defaults = UserDefaults(suiteName: "digest-test-\(UUID().uuidString)")!
            self.preferencesStore = PreferencesStore(defaults: defaults)
            self.preferencesStore.digestEnabled = digestEnabled
            self.scheduler = MockWeeklyDigestScheduler(initialStatus: status)
            self.coordinator = WeeklyDigestCoordinator(
                viewModel: viewModel,
                preferencesStore: preferencesStore,
                scheduler: scheduler,
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        }
    }

    private func makeEnv(
        digestEnabled: Bool,
        status: DigestAuthorizationStatus
    ) -> Environment {
        Environment(digestEnabled: digestEnabled, status: status)
    }
}

private func demoGrant(bundleID: String = "com.example.demo") -> PermissionGrant {
    PermissionGrant(
        service: .microphone,
        app: AppIdentity(bundleID: bundleID, displayName: bundleID),
        lastModified: Date(timeIntervalSince1970: 0)
    )
}

private func demoLaunchAgent() -> LaunchAgentItem {
    LaunchAgentItem(
        label: "com.example.demo",
        sourceDirectory: .userLaunchAgents,
        programPath: "/usr/local/bin/demo",
        programArguments: [],
        runAtLoad: true,
        keepAlive: false
    )
}
