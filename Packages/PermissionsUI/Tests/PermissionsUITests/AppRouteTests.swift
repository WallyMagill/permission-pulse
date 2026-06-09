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

    private func diffs(addedGrants: [PermissionGrant], from: Int64 = 41, to: Int64 = 42) -> SnapshotDiffs {
        SnapshotDiffs(
            fromID: SnapshotID(rawValue: from),
            toID: SnapshotID(rawValue: to),
            tcc: TCCGrantsDiff(added: addedGrants, removed: [], changed: []),
            btm: BTMItemsDiff(added: [], removed: [], changed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [])
        )
    }

    @Test("recentChangeEventCount uses yesterday diff when it has content")
    func countPrefersYesterday() {
        let vm = AppViewModel(
            latestDiffYesterday: diffs(addedGrants: [grant("a", .camera), grant("b", .microphone)]),
            latestDiffWeek: diffs(addedGrants: [grant("c", .camera)])
        )
        #expect(vm.recentChangeEventCount == 2)
    }

    @Test("recentChangeEventCount falls back to week diff when yesterday is empty")
    func countFallsBackToWeek() {
        let vm = AppViewModel(
            latestDiffYesterday: diffs(addedGrants: []),
            latestDiffWeek: diffs(addedGrants: [grant("c", .camera)])
        )
        #expect(vm.recentChangeEventCount == 1)
    }

    @Test("recentChangeEventCount is zero with no diffs")
    func countZeroWithNoDiffs() {
        #expect(AppViewModel().recentChangeEventCount == 0)
    }
}
