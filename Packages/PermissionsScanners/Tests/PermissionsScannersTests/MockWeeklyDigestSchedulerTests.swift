import Foundation
import Testing
import PermissionsCore
@testable import PermissionsScanners

@Suite struct MockWeeklyDigestSchedulerTests {
    @Test func recordsScheduleAndCancelCallsInOrder() async throws {
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
        try await scheduler.scheduleWeekly(
            identifier: "com.test.digest.weekly",
            weekday: 2, hour: 9, minute: 0,
            title: "Title", body: "Body"
        )
        await scheduler.cancelAll(matchingPrefix: "com.test.digest")

        let actions = await scheduler.recorded
        #expect(actions.count == 2)
        #expect(actions[0] == .scheduled(
            identifier: "com.test.digest.weekly",
            weekday: 2, hour: 9, minute: 0,
            title: "Title", body: "Body"
        ))
        #expect(actions[1] == .canceledAll(matchingPrefix: "com.test.digest"))

        let pending = await scheduler.pendingIdentifiers()
        #expect(pending.isEmpty)
    }

    @Test func returnsConfiguredAuthorizationStatus() async throws {
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .denied)
        let status = await scheduler.currentAuthorizationStatus()
        #expect(status == .denied)

        await scheduler.setAuthorizationStatus(.authorized)
        let next = await scheduler.currentAuthorizationStatus()
        #expect(next == .authorized)

        await scheduler.setRequestAuthorizationResult(.denied)
        let requested = try await scheduler.requestAuthorization()
        #expect(requested == .denied)
    }

    @Test func scheduleOneShotRecordsAndAddsToPending() async throws {
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
        try await scheduler.scheduleOneShot(
            identifier: "test.123",
            after: 5,
            title: "Hi",
            body: "Body"
        )
        let pending = await scheduler.pendingIdentifiers()
        #expect(pending.contains("test.123"))
        let actions = await scheduler.recorded
        #expect(actions.contains(where: { action in
            if case .scheduledOneShot(let id, let after, _, _) = action {
                return id == "test.123" && after == 5
            }
            return false
        }))
    }

    @Test func nextFireDatePopulatedForBothTriggerKinds() async throws {
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
        try await scheduler.scheduleWeekly(
            identifier: "weekly", weekday: 2, hour: 9, minute: 0,
            title: "T", body: "B"
        )
        try await scheduler.scheduleOneShot(
            identifier: "oneshot", after: 5,
            title: "T", body: "B"
        )
        let weeklyNext = await scheduler.nextFireDate(for: "weekly")
        let oneshotNext = await scheduler.nextFireDate(for: "oneshot")
        #expect(weeklyNext != nil)
        #expect(oneshotNext != nil)
        #expect(await scheduler.nextFireDate(for: "nonexistent") == nil)
    }

    @Test func cancelAllPrefixRemovesBothKinds() async throws {
        let scheduler = MockWeeklyDigestScheduler(initialStatus: .authorized)
        try await scheduler.scheduleWeekly(
            identifier: "com.example.digest.weekly", weekday: 2, hour: 9, minute: 0,
            title: "T", body: "B"
        )
        try await scheduler.scheduleOneShot(
            identifier: "com.example.digest.test.abc", after: 5,
            title: "T", body: "B"
        )
        try await scheduler.scheduleOneShot(
            identifier: "com.unrelated.thing", after: 5,
            title: "T", body: "B"
        )

        await scheduler.cancelAll(matchingPrefix: "com.example.digest")

        let pending = await scheduler.pendingIdentifiers()
        #expect(pending == ["com.unrelated.thing"])
    }
}
