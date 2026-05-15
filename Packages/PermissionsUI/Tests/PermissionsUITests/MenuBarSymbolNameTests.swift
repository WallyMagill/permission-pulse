import Foundation
import Testing
import PermissionsCore
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
}
