import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelAccessibilityTests {
    @Test func defaultLabelIsAppName() {
        #expect(AppViewModel().menuBarAccessibilityLabel == String(localized: "Permission Pulse"))
    }

    @Test func errorTakesPrecedence() {
        let vm = AppViewModel(tccScanError: .permissionDenied(reason: "x"))
        #expect(vm.menuBarAccessibilityLabel.contains("action needed"))
    }

    @Test func cameraInUseAnnounced() {
        let vm = AppViewModel(cameraInUse: true)
        #expect(vm.menuBarAccessibilityLabel.contains("camera"))
    }

    @Test func micInUseAnnounced() {
        let vm = AppViewModel(micInUse: true)
        #expect(vm.menuBarAccessibilityLabel.contains("microphone"))
    }

    @Test func micAndCameraInUseAnnounced() {
        let vm = AppViewModel(micInUse: true, cameraInUse: true)
        #expect(vm.menuBarAccessibilityLabel.contains("microphone and camera"))
    }

    @Test func unreviewedChangesAnnounced() {
        let latest = SnapshotID(rawValue: 99)
        let diff = SnapshotDiffs(
            fromID: SnapshotID(rawValue: 98),
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
            lastReviewedSnapshotID: nil,
            latestDiffYesterday: diff
        )
        #expect(vm.menuBarAccessibilityLabel.contains("unreviewed"))
    }
}
