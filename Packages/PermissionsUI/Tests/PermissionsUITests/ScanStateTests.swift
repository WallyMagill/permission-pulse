import Testing
@testable import PermissionsUI

@Suite("ScanState.showsScanningPlaceholder")
struct ScanStateTests {
    @Test("shows placeholder while scanning with nothing to show yet")
    func showsWhileScanningAndEmpty() {
        #expect(ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: true, hasError: false, isSearching: false
        ))
    }

    @Test("hidden when not scanning")
    func hiddenWhenNotScanning() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: false, isEmpty: true, hasError: false, isSearching: false
        ))
    }

    @Test("hidden when there is already data")
    func hiddenWhenData() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: false, hasError: false, isSearching: false
        ))
    }

    @Test("hidden when an error is present — the error state owns the surface")
    func hiddenWhenError() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: true, hasError: true, isSearching: false
        ))
    }

    @Test("hidden while searching — a search miss is its own state")
    func hiddenWhenSearching() {
        #expect(!ScanState.showsScanningPlaceholder(
            isScanning: true, isEmpty: true, hasError: false, isSearching: true
        ))
    }
}
