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
}
