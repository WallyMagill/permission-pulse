import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct WhatChangedViewModelTests {
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
