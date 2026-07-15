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
        let result = await env.coordinator.reconcileSchedule()

        #expect(result == .disabled)
        let actions = await env.scheduler.recorded
        #expect(actions.contains { if case .canceledAll = $0 { true } else { false } })
        #expect(!actions.contains { if case .scheduled = $0 { true } else { false } })
    }

    @Test func reconcileScheduleWhenEnabledAndAuthorizedSchedulesOnce() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let result = await env.coordinator.reconcileSchedule()

        guard case .scheduled(let nextFire) = result else {
            Issue.record("Expected .scheduled, got \(result)")
            return
        }
        #expect(nextFire != nil)
        let pending = await env.scheduler.pendingIdentifiers()
        #expect(pending.count == 1)
        #expect(pending.first == WeeklyDigestCoordinator.weeklyIdentifier)
    }

    @Test func reconcileScheduleWhenNotAuthorizedReturnsTypedResult() async throws {
        let env = makeEnv(digestEnabled: true, status: .denied)

        let result = await env.coordinator.reconcileSchedule()

        #expect(result == .notAuthorized)
        #expect(await env.scheduler.pendingIdentifiers().isEmpty)
    }

    @Test func changedScheduleReplacesPendingRequestAndRefreshesNextFire() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        env.preferencesStore.digestWeekday = 2
        env.preferencesStore.digestHour = 9
        env.preferencesStore.digestMinute = 0
        let initialResult = await env.coordinator.reconcileSchedule()
        guard case .scheduled(let initialNextFire) = initialResult else {
            Issue.record("Expected initial schedule, got \(initialResult)")
            return
        }

        env.preferencesStore.digestWeekday = 6
        env.preferencesStore.digestHour = 17
        env.preferencesStore.digestMinute = 45
        let changedResult = await env.coordinator.reconcileSchedule()

        guard case .scheduled(let changedNextFire) = changedResult else {
            Issue.record("Expected changed schedule, got \(changedResult)")
            return
        }
        let pending = await env.scheduler.pendingIdentifiers()
        let actualNextFire = await env.coordinator.nextWeeklyFireDate()
        let scheduledActions: [(weekday: Int, hour: Int, minute: Int)] =
            await env.scheduler.recorded.compactMap { action in
                guard case .scheduled(_, let weekday, let hour, let minute, _, _) = action else {
                    return nil
                }
                return (weekday: weekday, hour: hour, minute: minute)
            }
        #expect(pending == [WeeklyDigestCoordinator.weeklyIdentifier])
        #expect(scheduledActions.last?.0 == 6)
        #expect(scheduledActions.last?.1 == 17)
        #expect(scheduledActions.last?.2 == 45)
        #expect(changedNextFire == actualNextFire)
        #expect(changedNextFire != initialNextFire)
    }

    @Test func schedulingFailureReturnsExactMessageAndCanBeRetried() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        await env.scheduler.setNextScheduleError(InjectedSchedulingError())

        let failed = await env.coordinator.reconcileSchedule()

        #expect(failed == .failed("injected scheduling failure"))
        #expect(await env.scheduler.pendingIdentifiers().isEmpty)

        let retried = await env.coordinator.reconcileSchedule()
        guard case .scheduled(let nextFire) = retried else {
            Issue.record("Expected retry to schedule, got \(retried)")
            return
        }
        #expect(nextFire != nil)
        #expect(await env.scheduler.pendingIdentifiers() == [WeeklyDigestCoordinator.weeklyIdentifier])
    }

    @Test func reconcileScheduleCalledTwiceIsIdempotent() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        _ = await env.coordinator.reconcileSchedule()
        _ = await env.coordinator.reconcileSchedule()

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

    @Test func composeTCCChangedOnlyProducesChangedSentence() {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let before = demoGrant(authValue: 2)
        let after = demoGrant(authValue: 3)
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 1),
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(
                added: [],
                removed: [],
                changed: [DomainChange(before: before, after: after)]
            ),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [])
        )

        #expect(
            env.coordinator.composeDigestBody(diff: diff).body
                == String(localized: "1 changed in the last week.")
        )
    }

    @Test func composeTwoTCCChangesProducesPluralChangedSentence() {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        let firstBefore = demoGrant(bundleID: "com.example.first", authValue: 2)
        let firstAfter = demoGrant(bundleID: "com.example.first", authValue: 3)
        let secondBefore = demoGrant(bundleID: "com.example.second", authValue: 3)
        let secondAfter = demoGrant(bundleID: "com.example.second", authValue: 2)
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 1),
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(
                added: [],
                removed: [],
                changed: [
                    DomainChange(before: firstBefore, after: firstAfter),
                    DomainChange(before: secondBefore, after: secondAfter),
                ]
            ),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [])
        )

        #expect(
            env.coordinator.composeDigestBody(diff: diff).body
                == String(localized: "2 changed in the last week.")
        )
    }

    @Test func handleAuthorizationToggleOffCancelsPending() async throws {
        let env = makeEnv(digestEnabled: true, status: .authorized)
        env.preferencesStore.digestEnabled = true
        _ = await env.coordinator.reconcileSchedule()
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
        _ = await env.coordinator.reconcileSchedule()
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

private func demoGrant(
    bundleID: String = "com.example.demo",
    authValue: Int = 2
) -> PermissionGrant {
    PermissionGrant(
        service: .microphone,
        app: AppIdentity(bundleID: bundleID, displayName: bundleID),
        lastModified: Date(timeIntervalSince1970: 0),
        authValue: authValue
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

private struct InjectedSchedulingError: LocalizedError, Sendable {
    var errorDescription: String? { "injected scheduling failure" }
}
