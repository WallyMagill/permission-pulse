import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct WhatChangedViewModelTests {
    @Test func recentChangeEventCountIncludesTCCAuthorizationChange() {
        let before = PermissionGrant(
            service: .photos,
            app: AppIdentity(bundleID: "com.example.photos", displayName: "Photos"),
            lastModified: Date(timeIntervalSince1970: 0),
            authValue: 2
        )
        let after = PermissionGrant(
            service: .photos,
            app: before.app,
            lastModified: Date(timeIntervalSince1970: 1),
            authValue: 3
        )
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 1),
            toID: SnapshotID(rawValue: 2),
            tcc: TCCGrantsDiff(
                added: [],
                removed: [],
                changed: [DomainChange(before: before, after: after)]
            ),
            btm: BTMItemsDiff(added: [], removed: [], changed: []),
            launchAgents: LaunchAgentsDiff(added: [], removed: [], changed: [])
        )

        #expect(AppViewModel(latestDiffYesterday: diff).recentChangeEventCount == 1)
    }

    @Test func hasUnreviewedChangesFalseWhenNoSnapshotYet() {
        let vm = AppViewModel()
        #expect(!vm.hasUnreviewedChanges)
    }

    @Test func hasUnreviewedChangesTrueWhenLatestUnreviewedWithContent() {
        let latest = SnapshotID(rawValue: 42)
        let yesterdayDiff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 41),
            toID: latest,
            tcc: TCCGrantsDiff(added: [], removed: []),
            btm: BTMItemsDiff(added: [], removed: []),
            launchAgents: LaunchAgentsDiff(
                added: [
                    LaunchAgentItem(
                        label: "com.example.new",
                        sourceDirectory: .userLaunchAgents,
                        programPath: "/bin/new",
                        programArguments: [],
                        runAtLoad: true,
                        keepAlive: false
                    ),
                ],
                removed: []
            )
        )

        let vm = AppViewModel(
            latestSnapshotID: latest,
            lastReviewedSnapshotID: SnapshotID(rawValue: 40),
            latestDiffYesterday: yesterdayDiff
        )
        #expect(vm.hasUnreviewedChanges)

        // Mark reviewed -> flag clears.
        vm.lastReviewedSnapshotID = latest
        #expect(!vm.hasUnreviewedChanges)
    }
}
