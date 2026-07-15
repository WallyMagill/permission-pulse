import Foundation
import Testing
import PermissionsCore
@testable import PermissionsUI

@Suite @MainActor struct AppViewModelAvailabilityTests {
    @Test func scanAvailabilityDefaultsToNever() {
        let vm = AppViewModel()

        #expect(vm.tccAvailability == .never)
        #expect(vm.btmAvailability == .never)
        #expect(vm.launchAgentAvailability == .never)
        #expect(vm.tccScanError == nil)
        #expect(vm.btmScanError == nil)
        #expect(vm.launchAgentScanError == nil)
    }

    @Test func compatibilityErrorsAreComputedFromAvailability() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let error = ScannerError.schemaMismatch(detail: "changed")
        let vm = AppViewModel(
            tccAvailability: .failed(lastSuccessful: date, error: error)
        )

        #expect(vm.tccScanError == error)
        vm.tccAvailability = .complete(lastUpdated: date)
        #expect(vm.tccScanError == nil)
    }

    @Test func compatibilityErrorSetterUpdatesAvailabilityWithoutSecondTruth() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let vm = AppViewModel(tccAvailability: .complete(lastUpdated: date))
        let error = ScannerError.temporarilyUnavailable(reason: "busy")

        vm.tccScanError = error

        #expect(vm.tccAvailability == .failed(lastSuccessful: date, error: error))
        vm.tccScanError = nil
        #expect(vm.tccAvailability == .never)
    }

    @Test func availabilityFlagsRemainIndependentFromScanAvailability() {
        let vm = AppViewModel()
        vm.snapshotStoreUnavailable = true
        vm.diffUnavailable = true

        #expect(vm.snapshotStoreUnavailable)
        #expect(vm.diffUnavailable)
        #expect(vm.tccAvailability == .never)
    }

    @Test(arguments: [
        ScannerSource.userTCCDatabase,
        .systemTCCDatabase,
        .userLaunchAgents,
        .libraryLaunchAgents,
        .libraryLaunchDaemons,
        .entries,
    ])
    func bannerMapsEveryWarningSourceToVisibleLocalizedCopy(source: ScannerSource) {
        let text = ScanAvailabilityBanner.warningText(
            for: ScannerWarning(source: source, omittedCount: source == .entries ? 3 : nil)
        )

        #expect(!text.isEmpty)
        #expect(text != String(describing: source))
    }

    @Test func bannerAccessibilityNamesCompleteDegradedStaleAndNeverStates() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let complete = ScanAvailabilityBanner(
            availability: .complete(lastUpdated: date),
            domainName: "Permissions"
        )
        let degraded = ScanAvailabilityBanner(
            availability: .degraded(
                lastUpdated: date,
                warnings: [.init(source: .systemTCCDatabase)]
            ),
            domainName: "Permissions"
        )
        let stale = ScanAvailabilityBanner(
            availability: .failed(
                lastSuccessful: date,
                error: .temporarilyUnavailable(reason: "busy")
            ),
            domainName: "Permissions"
        )
        let never = ScanAvailabilityBanner(availability: .never, domainName: "Permissions")

        #expect(complete.accessibilityText.localizedCaseInsensitiveContains("complete"))
        #expect(degraded.accessibilityText.localizedCaseInsensitiveContains("degraded"))
        #expect(degraded.accessibilityText.localizedCaseInsensitiveContains("updated"))
        #expect(stale.accessibilityText.localizedCaseInsensitiveContains("stale"))
        #expect(stale.accessibilityText.localizedCaseInsensitiveContains("last known"))
        #expect(never.accessibilityText.localizedCaseInsensitiveContains("not yet scanned"))
    }

    @Test func multiWarningBannerAccessibilityDoesNotDoublePunctuation() {
        let banner = ScanAvailabilityBanner(
            availability: .degraded(
                lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
                warnings: [
                    .init(source: .systemTCCDatabase),
                    .init(source: .entries, omittedCount: 2),
                ]
            ),
            domainName: "Permissions"
        )

        #expect(!banner.accessibilityText.contains(".."))
    }

    @Test func failedBannerWithoutHistoryIsNotLabeledAsStale() {
        let banner = ScanAvailabilityBanner(
            availability: .failed(
                lastSuccessful: nil,
                error: .temporarilyUnavailable(reason: "busy")
            ),
            domainName: "Permissions"
        )

        #expect(banner.headline.localizedCaseInsensitiveContains("failed"))
        #expect(!banner.headline.localizedCaseInsensitiveContains("stale"))
    }
}
