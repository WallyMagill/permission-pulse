import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct ChangeAlertTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func noEntriesPostsNothing() {
        #expect(ChangeAlert.make(for: diff(), dismissals: nil, asOf: now) == nil)
        #expect(ChangeAlert.make(for: nil, dismissals: nil, asOf: now) == nil)
    }

    @Test func dismissedEntriesPostNothing() throws {
        let store = DismissedDiffEntryStore(
            defaults: try #require(UserDefaults(suiteName: "change-alert-\(UUID().uuidString)"))
        )
        let changes = diff(grants: [grant("us.zoom.xos", "Zoom")])
        store.dismissForever(key: changes.entries[0].id)

        #expect(ChangeAlert.make(for: changes, dismissals: store, asOf: now) == nil)
    }

    @Test func oneEntryUsesItsSummary() {
        let alert = ChangeAlert.make(for: diff(grants: [grant("us.zoom.xos", "Zoom")]), dismissals: nil, asOf: now)

        #expect(alert?.title == "Permission Pulse: something changed")
        #expect(alert?.body == "Granted Screen Recording to Zoom")
    }

    @Test func severalEntriesCountTheRest() {
        let alert = ChangeAlert.make(
            for: diff(grants: [grant("us.zoom.xos", "Zoom"), grant("com.b", "Bee"), grant("com.c", "Sea")]),
            dismissals: nil,
            asOf: now
        )

        #expect(alert?.body == "3 changes: Granted Screen Recording to Zoom and 2 other changes.")
    }

    @Test func oneOtherChangeIsSingular() {
        let alert = ChangeAlert.make(
            for: diff(grants: [grant("us.zoom.xos", "Zoom"), grant("com.b", "Bee")]),
            dismissals: nil,
            asOf: now
        )

        #expect(alert?.body == "2 changes: Granted Screen Recording to Zoom and 1 other change.")
    }

    @Test func uncomparedDomainIsIgnored() {
        let alert = ChangeAlert.make(
            for: diff(grants: [grant("us.zoom.xos", "Zoom")], uncompared: [.tcc: .itemsUnreadable]),
            dismissals: nil,
            asOf: now
        )

        #expect(alert == nil)
    }

    private func diff(
        grants: [PermissionGrant] = [],
        uncompared: [HistoryDomain: UncomparedReason] = [:]
    ) -> SnapshotDiffs {
        SnapshotDiffs(
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(added: grants, removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: []),
            uncompared: uncompared
        )
    }

    private func grant(_ bundleID: String, _ name: String) -> PermissionGrant {
        PermissionGrant(
            service: .screenRecording,
            app: AppIdentity(bundleID: bundleID, displayName: name),
            lastModified: Date(timeIntervalSince1970: 0)
        )
    }
}
