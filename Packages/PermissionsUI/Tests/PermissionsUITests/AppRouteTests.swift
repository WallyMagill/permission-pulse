import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite("AppRoute")
struct AppRouteTests {
    @Test("Every route maps to its sidebar section")
    func routeSidebarMapping() {
        #expect(AppRoute.overview.sidebarItem == .overview)
        #expect(AppRoute.permissions(selectAppKey: nil).sidebarItem == .permissions)
        #expect(AppRoute.permissions(selectAppKey: "com.zoom.xos").sidebarItem == .permissions)
        #expect(AppRoute.launchAgents(selectID: nil).sidebarItem == .launchAgents)
        #expect(AppRoute.backgroundItems(selectID: nil).sidebarItem == .backgroundItems)
        #expect(AppRoute.recentChanges.sidebarItem == .recentChanges)
        #expect(AppRoute.staleApps.sidebarItem == .staleApps)
        #expect(AppRoute.recentChangesLastSevenDays.sidebarItem == .recentChanges)
    }

    @Test("Recent Changes routes pick their window")
    func recentChangesWindows() {
        #expect(AppRoute.recentChanges.recentChangesWindow == .sinceLastReview)
        #expect(AppRoute.recentChangesLastSevenDays.recentChangesWindow == .lastSevenDays)
        #expect(AppRoute.overview.recentChangesWindow == nil)
    }
}

@Suite("AppViewModel routing")
@MainActor
struct AppViewModelRoutingTests {
    private func grant(_ bundleID: String, _ service: PermissionService) -> PermissionGrant {
        PermissionGrant(
            service: service,
            app: AppIdentity(bundleID: bundleID, displayName: bundleID, bundlePath: nil),
            lastModified: Date(timeIntervalSince1970: 0),
            automationTarget: nil,
            authValue: 2
        )
    }

    private func diffs(addedGrants: [PermissionGrant]) -> SnapshotDiffs {
        SnapshotDiffs(
            toID: SnapshotID(rawValue: 42),
            tcc: TCCGrantsDiff(added: addedGrants, removed: [], changed: []),
            btm: BTMItemsDiff(added: [], removed: [], changed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [], changed: [])
        )
    }

    private func unreviewed(_ sinceReview: SnapshotDiffs?, week: SnapshotDiffs? = nil) -> AppViewModel {
        AppViewModel(
            latestSnapshotID: SnapshotID(rawValue: 42),
            lastReviewedSnapshotID: SnapshotID(rawValue: 41),
            latestDiffSinceReview: sinceReview,
            latestDiffWeek: week
        )
    }

    private func btmItem(identifier: String, disposition: BTMItem.Disposition) -> BTMItem {
        BTMItem(
            identifier: identifier,
            name: identifier,
            type: .app,
            disposition: disposition,
            scope: .user,
            modificationDate: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("unreviewedChangeCount counts the since-last-review diff only")
    func countUsesSinceReviewWindow() {
        let vm = unreviewed(
            diffs(addedGrants: [grant("a", .camera), grant("b", .microphone)]),
            week: diffs(addedGrants: [grant("c", .camera)])
        )
        #expect(vm.unreviewedChangeCount == 2)
        #expect(unreviewed(diffs(addedGrants: []), week: diffs(addedGrants: [grant("c", .camera)]))
            .unreviewedChangeCount == 0)
    }

    @Test("dismissed and snoozed changes are not counted")
    func countSkipsDismissedEntries() throws {
        let defaults = try #require(UserDefaults(suiteName: "routing-\(UUID().uuidString)"))
        let store = DismissedDiffEntryStore(defaults: defaults)
        let vm = unreviewed(diffs(addedGrants: [grant("a", .camera), grant("b", .microphone), grant("c", .photos)]))
        vm.dismissedDiffEntries = store
        let entries = vm.visibleEntries(of: vm.latestDiffSinceReview)
        store.dismissForever(key: entries[0].id)
        store.snooze(key: entries[1].id, until: Date().addingTimeInterval(3600))

        #expect(vm.unreviewedChangeCount == 1)
        #expect(vm.visibleEntries(of: vm.latestDiffSinceReview, asOf: Date().addingTimeInterval(7200)).count == 2)
    }

    @Test("a coverage-only diff raises no badge")
    func coverageOnlyDiffIsNotUnreviewed() {
        let coverageOnly = SnapshotDiffs(
            toID: SnapshotID(rawValue: 42),
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: []),
            uncompared: [.launchAgents: .itemsUnreadable]
        )
        #expect(!unreviewed(coverageOnly).hasUnreviewedChanges)
    }

    @Test("nothing is unreviewed while Recent Changes is on screen")
    func countIsZeroWhileViewing() {
        let vm = unreviewed(diffs(addedGrants: [grant("a", .camera)]))
        vm.isViewingRecentChanges = true
        #expect(vm.unreviewedChangeCount == 0)
        vm.isViewingRecentChanges = false
        #expect(vm.unreviewedChangeCount == 1)
    }

    @Test("unreviewedChangeCount counts BTM disposition flip as one event")
    func countBTMFlip() {
        let before = btmItem(identifier: "com.example.app", disposition: .enabled)
        let after = btmItem(identifier: "com.example.app", disposition: .disabled)
        let diffsWithFlip = SnapshotDiffs(
            toID: SnapshotID(rawValue: 42),
            tcc: TCCGrantsDiff(added: [], removed: [], changed: []),
            btm: BTMItemsDiff(added: [], removed: [], changed: [DomainChange(before: before, after: after)]),
            launchAgents: LaunchAgentsDiff(added: [], removed: [], changed: [])
        )
        #expect(unreviewed(diffsWithFlip).unreviewedChangeCount == 1)
    }

    @Test("Skip forever drops the stale app from the count at once")
    func skipStaleAppUpdatesCount() throws {
        let defaults = try #require(UserDefaults(suiteName: "stale-skip-\(UUID().uuidString)"))
        let store = DismissedStaleAppStore(defaults: defaults)
        let stale = ["com.example.kept", "com.example.skipped"].map { bundleID in
            StaleApp(
                app: AppIdentity(bundleID: bundleID, displayName: bundleID),
                lastUsedDate: Date(timeIntervalSince1970: 0),
                dateSource: .spotlight,
                daysSinceUsed: 200,
                grantedServices: [.camera]
            )
        }
        let vm = AppViewModel(staleApps: stale)

        vm.skipStaleAppForever(stableKey: "bundle:com.example.skipped", in: store)

        #expect(vm.staleApps.map(\.app.bundleID) == ["com.example.kept"])
        #expect(store.contains(stableKey: "bundle:com.example.skipped"))
    }

    @Test("lastScanDate is nil by default")
    func lastScanDateNilByDefault() {
        #expect(AppViewModel().lastScanDate == nil)
    }
}
