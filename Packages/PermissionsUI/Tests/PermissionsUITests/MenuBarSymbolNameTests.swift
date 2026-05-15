import Foundation
import Testing
import PermissionsCore
import PermissionsStore
@testable import PermissionsUI

@Suite @MainActor struct MenuBarSymbolNameTests {
    @Test func idleReturnsShield() {
        let vm = AppViewModel()
        #expect(vm.menuBarSymbolName == "shield.lefthalf.filled")
    }

    @Test func micOnlyReturnsMic() {
        let vm = AppViewModel(micInUse: true)
        #expect(vm.menuBarSymbolName == "mic.fill")
    }

    @Test func cameraOnlyReturnsVideo() {
        let vm = AppViewModel(cameraInUse: true)
        #expect(vm.menuBarSymbolName == "video.fill")
    }

    @Test func micAndCameraReturnsCombinedSymbol() {
        let vm = AppViewModel(micInUse: true, cameraInUse: true)
        #expect(vm.menuBarSymbolName == "video.badge.waveform")
    }

    @Test func tccErrorBeatsMicAndCamera() {
        let vm = AppViewModel(
            tccScanError: .permissionDenied(reason: "FDA needed"),
            micInUse: true,
            cameraInUse: true
        )
        #expect(vm.menuBarSymbolName == "exclamationmark.shield.fill")
    }

    @Test func btmErrorAloneStillFlipsToError() {
        let vm = AppViewModel(btmScanError: .permissionDenied(reason: "FDA needed"))
        #expect(vm.menuBarSymbolName == "exclamationmark.shield.fill")
    }

    @Test func schemaMismatchAlsoFlipsToError() {
        let vm = AppViewModel(tccScanError: .schemaMismatch(detail: "missing column"))
        #expect(vm.menuBarSymbolName == "exclamationmark.shield.fill")
    }

    @Test func bothErrorsFlipToError() {
        let vm = AppViewModel(
            tccScanError: .permissionDenied(reason: "FDA"),
            btmScanError: .permissionDenied(reason: "FDA")
        )
        #expect(vm.menuBarSymbolName == "exclamationmark.shield.fill")
    }

    @Test func unreviewedChangesBeatsMicAndCamera() {
        let vm = unreviewedViewModel(micInUse: true, cameraInUse: true)
        #expect(vm.menuBarSymbolName == "bell.badge.fill")
    }

    @Test func errorBeatsUnreviewedChanges() {
        let vm = unreviewedViewModel()
        vm.tccScanError = .permissionDenied(reason: "FDA")
        #expect(vm.menuBarSymbolName == "exclamationmark.shield.fill")
    }

    @Test func reviewedStateReturnsToIdleWhenLatestEqualsReviewed() {
        let vm = unreviewedViewModel()
        #expect(vm.menuBarSymbolName == "bell.badge.fill")
        vm.lastReviewedSnapshotID = vm.latestSnapshotID
        #expect(vm.menuBarSymbolName == "shield.lefthalf.filled")
    }

    private func unreviewedViewModel(
        micInUse: Bool = false,
        cameraInUse: Bool = false
    ) -> AppViewModel {
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
        return AppViewModel(
            micInUse: micInUse,
            cameraInUse: cameraInUse,
            latestSnapshotID: latest,
            lastReviewedSnapshotID: nil,
            latestDiffYesterday: diff
        )
    }
}
